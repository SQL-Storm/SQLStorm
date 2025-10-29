-- {"query": "2603.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1632} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        p.CreationDate AS TagExcerptCreationDate,
        p2.CreationDate AS TagWikiCreationDate,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.CreationDate DESC) AS ExcerptRank,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p2.CreationDate DESC) AS WikiRank
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId AND p.PostTypeId = 5
    LEFT JOIN Posts p2 ON p2.Id = t.WikiPostId AND p2.PostTypeId = 5
),
TopTags AS (
    SELECT DISTINCT
        Id,
        TagName,
        Count,
        TagExcerptCreationDate,
        TagWikiCreationDate
    FROM RecursiveTagHierarchy
    WHERE ExcerptRank = 1 AND WikiRank = 1
    AND Count > 1000
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes,
        CASE WHEN COUNT(p.Id) > 0 THEN CAST(u.Reputation AS float)/COUNT(p.Id) ELSE 0 END AS ReputationPerPost
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
HighlyActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        QuestionCount,
        AnswerCount,
        TotalUpVotes,
        TotalDownVotes,
        ReputationPerPost,
        RANK() OVER (ORDER BY Reputation DESC, TotalUpVotes DESC) AS UserRank
    FROM UserPostStats
),
RecentActiveQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentRank
    FROM Posts p
    INNER JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.CreationDate > now() - interval '30 days'
),
TopQuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        au.DisplayName AS AnswerOwnerDisplayName,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAcceptedAnswer,
        (a.Score * 1.5 + q.Score) * 
        (1 + COALESCE((SELECT AVG(score_window) FROM (
            SELECT AVG(score) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS score_window
            FROM Posts
            WHERE PostTypeId = 2 AND OwnerUserId = a.OwnerUserId
        ) AS avg_scores), 0)) AS CompositeAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users au ON au.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
      AND q.CreationDate BETWEEN now() - interval '90 days' AND now()
      AND q.Score > 5
),
ClosedQuestionsWithReasons AS (
    SELECT 
        ph.PostId,
        ph.CreationDate AS ClosedDate,
        crt.Name AS CloseReasonName,
        p.Title,
        p.Score,
        u.DisplayName AS OwnerName
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS int)
    INNER JOIN Posts p ON p.Id = ph.PostId
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE ph.PostHistoryTypeId = 10  -- Post Closed
      AND ph.CreationDate > now() - interval '180 days'
),
QuestionsCommentsStats AS (
    SELECT 
        p.Id AS QuestionId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate,
        STRING_AGG(DISTINCT COALESCE(NULLIF(c.UserDisplayName, ''), 'Anonymous'), ', ' ORDER BY c.CreationDate DESC) AS Commenters
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)
SELECT
    h.UserRank,
    h.DisplayName AS UserName,
    h.Reputation,
    h.QuestionCount,
    h.AnswerCount,
    h.TotalUpVotes,
    h.TotalDownVotes,
    ROUND(h.ReputationPerPost, 2) AS ReputationPerPost,
    q.Title AS RecentQuestionTitle,
    q.CreationDate AS RecentQuestionDate,
    ta.AnswerId,
    ta.AnswerOwnerDisplayName,
    ta.CompositeAnswerScore,
    cq.ClosedDate,
    cq.CloseReasonName,
    cq.Title AS ClosedQuestionTitle,
    qc.TotalComments,
    COALESCE(qc.AvgCommentScore,0) AS AvgCommentScore,
    qc.Commenters,
    tt.TagName AS PopularTag,
    tt.Count AS TagUsageCount,
    CONCAT('User since: ', TO_CHAR(u.CreationDate, 'YYYY-MM-DD'), ', Last Access: ', TO_CHAR(u.LastAccessDate, 'YYYY-MM-DD')) AS UserActivityPeriod,
    CASE 
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN CONCAT('Website: ', u.WebsiteUrl) 
        ELSE 'No website' 
    END AS WebsiteInfo,
    CASE 
        WHEN p.Score > 50 THEN 'Hot Question' 
        WHEN p.Score BETWEEN 10 AND 50 THEN 'Popular Question' 
        ELSE 'Regular Question' 
    END AS QuestionPopularityQueue
FROM HighlyActiveUsers h
JOIN Users u ON u.Id = h.UserId
LEFT JOIN RecentActiveQuestions q ON q.OwnerUserId = h.UserId AND q.RecentRank = 1
LEFT JOIN TopQuestionsWithAnswers ta ON ta.QuestionId = q.Id
LEFT JOIN ClosedQuestionsWithReasons cq ON cq.PostId = q.Id
LEFT JOIN QuestionsCommentsStats qc ON qc.QuestionId = q.Id
LEFT JOIN LATERAL (
    SELECT TagName, Count FROM TopTags tt2
    WHERE q.Tags LIKE CONCAT('%', tt2.TagName , '%')
    ORDER BY Count DESC
    LIMIT 1
) tt ON true
LEFT JOIN Posts p ON p.Id = q.Id
WHERE h.UserRank <= 100
ORDER BY h.UserRank, ta.CompositeAnswerScore DESC NULLS LAST, q.CreationDate DESC
LIMIT 200;
