-- {"query": "46015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 34410, "output_tokens": 27250} 

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT v.Id) AS VotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2020-01-01' 
        AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
TopQuestionMetrics AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate AS QuestionCreationDate,
        u.DisplayName AS AuthorName,
        u.Reputation AS AuthorReputation,
        COUNT(DISTINCT a.Id) AS ActualAnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS BestAnswerScore,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvoteCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvoteCount,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT ph.Id) AS EditCount,
        string_agg(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS TagList
    FROM Posts q
    JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Votes v ON q.Id = v.PostId
    LEFT JOIN Comments c ON q.Id = c.PostId
    LEFT JOIN PostHistory ph ON q.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT LATERAL (
        SELECT UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS tag
    ) AS qt ON true
    LEFT JOIN Tags t ON qt.tag = t.TagName
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= '2019-01-01'
        AND q.Score > 5
        AND q.ViewCount > 100
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.CreationDate, u.DisplayName, u.Reputation
),
TagPerformanceAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.Id) AS QuestionsWithTag,
        AVG(p.Score) AS AvgQuestionScore,
        AVG(p.ViewCount) AS AvgViewCount,
        AVG(p.AnswerCount) AS AvgAnswerCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
        COUNT(DISTINCT pl.Id) AS LinkedQuestions,
        COUNT(DISTINCT b.UserId) AS ExpertsWithBadge
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Badges b ON b.Name LIKE '%' || t.TagName || '%' AND b.TagBased = 1
    WHERE t.Count > 50
        AND p.PostTypeId = 1
        AND p.CreationDate >= '2018-01-01'
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 10
),
CrossJoinedAnalysis AS (
    SELECT 
        uem.UserId,
        uem.DisplayName,
        uem.Reputation,
        uem.TotalPosts,
        uem.QuestionCount,
        uem.AnswerCount,
        uem.BadgeCount,
        tqm.QuestionId,
        tqm.Title,
        tqm.QuestionScore,
        tqm.ViewCount,
        tqm.AvgAnswerScore,
        tpa.TagName,
        tpa.AvgQuestionScore AS TagAvgScore,
        tpa.AvgViewCount AS TagAvgViews,
        RANK() OVER (PARTITION BY uem.UserId ORDER BY tqm.QuestionScore DESC) AS UserQuestionRank,
        DENSE_RANK() OVER (PARTITION BY tpa.TagName ORDER BY tqm.ViewCount DESC) AS TagViewRank,
        ROW_NUMBER() OVER (ORDER BY uem.Reputation DESC, tqm.QuestionScore DESC) AS OverallRank
    FROM UserEngagementMetrics uem
    CROSS JOIN TopQuestionMetrics tqm
    CROSS JOIN TagPerformanceAnalysis tpa
    WHERE tqm.TagList LIKE '%' || tpa.TagName || '%'
        AND uem.Reputation > 500
        AND tqm.QuestionScore > 10
)
SELECT 
    cja.DisplayName,
    cja.Reputation,
    cja.TotalPosts,
    cja.BadgeCount,
    cja.Title AS QuestionTitle,
    cja.QuestionScore,
    cja.ViewCount,
    cja.TagName,
    cja.TagAvgScore,
    cja.UserQuestionRank,
    cja.TagViewRank,
    cja.OverallRank,
    CASE 
        WHEN cja.Reputation > 10000 AND cja.BadgeCount > 20 THEN 'Expert'
        WHEN cja.Reputation > 5000 AND cja.BadgeCount > 10 THEN 'Advanced'
        WHEN cja.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserTier,
    ROUND(cja.QuestionScore::numeric / NULLIF(cja.TagAvgScore, 0), 2) AS ScoreRatio,
    ROUND(cja.ViewCount::numeric / NULLIF(cja.TagAvgViews, 0), 2) AS ViewRatio
FROM CrossJoinedAnalysis cja
WHERE cja.OverallRank <= 1000
    AND cja.UserQuestionRank <= 50
    AND cja.TagViewRank <= 100
ORDER BY cja.OverallRank, cja.Reputation DESC, cja.QuestionScore DESC
LIMIT 500;
