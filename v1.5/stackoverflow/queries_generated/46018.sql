-- {"query": "46018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2067}

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
QuestionAnswerStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate AS QuestionCreationDate,
        q.OwnerUserId AS QuestionOwnerId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerId,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600.0 AS HoursToAnswer
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.CreationDate >= '2021-01-01'
        AND q.Score >= 5
        AND q.AnswerCount >= 2
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT qas.QuestionId) AS QuestionsInAnalysis,
        AVG(qas.QuestionScore) AS AvgQuestionScore,
        AVG(qas.ViewCount) AS AvgViews,
        AVG(qas.AnswerCount) AS AvgAnswers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qas.HoursToAnswer) AS MedianTimeToAnswer,
        COUNT(DISTINCT CASE WHEN qas.IsAccepted = 1 THEN qas.AnswerId END)::FLOAT / 
            NULLIF(COUNT(DISTINCT qas.QuestionId), 0) AS AcceptanceRate
    FROM Tags t
    INNER JOIN QuestionAnswerStats qas ON qas.Tags LIKE '%<' || t.TagName || '>%'
    GROUP BY t.Id, t.TagName, t.Count
    HAVING COUNT(DISTINCT qas.QuestionId) >= 10
),
TopContributors AS (
    SELECT 
        uem.UserId,
        uem.DisplayName,
        uem.Reputation,
        uem.TotalPosts,
        uem.QuestionCount,
        uem.AnswerCount,
        uem.AvgPostScore,
        uem.BadgeCount,
        COALESCE(SUM(CASE WHEN qas.IsAccepted = 1 THEN 1 ELSE 0 END), 0) AS AcceptedAnswerCount,
        COALESCE(AVG(qas.AnswerScore), 0) AS AvgAnswerScore,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        RANK() OVER (ORDER BY uem.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY uem.TotalPosts DESC) AS ActivityRank
    FROM UserEngagementMetrics uem
    LEFT JOIN QuestionAnswerStats qas ON uem.UserId = qas.AnswerOwnerId
    LEFT JOIN Votes v ON uem.UserId = v.UserId AND v.VoteTypeId IN (2, 3)
    GROUP BY uem.UserId, uem.DisplayName, uem.Reputation, uem.TotalPosts, 
             uem.QuestionCount, uem.AnswerCount, uem.AvgPostScore, uem.BadgeCount
),
InteractionPatterns AS (
    SELECT 
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS RegularLinks,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateLinks,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors
    FROM PostLinks pl
    INNER JOIN Posts p ON pl.PostId = p.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.CreationDate >= '2021-01-01'
    GROUP BY pl.PostId
)
SELECT 
    tp.TagName,
    tp.TagUsageCount,
    tp.AvgQuestionScore,
    tp.AvgViews,
    tp.AvgAnswers,
    tp.MedianTimeToAnswer,
    tp.AcceptanceRate,
    tc.DisplayName AS TopContributor,
    tc.Reputation AS TopContributorReputation,
    tc.AcceptedAnswerCount,
    tc.AvgAnswerScore,
    tc.ReputationRank,
    COALESCE(AVG(ip.LinkedPostCount), 0) AS AvgLinksPerPost,
    COALESCE(AVG(ip.EditCount), 0) AS AvgEditsPerPost,
    COUNT(DISTINCT qas.QuestionId) AS TotalQuestionsAnalyzed,
    SUM(qas.ViewCount) AS TotalViews,
    CORR(qas.QuestionScore, qas.AnswerCount) AS ScoreAnswerCorrelation
FROM TagPerformance tp
INNER JOIN QuestionAnswerStats qas ON qas.Tags LIKE '%<' || tp.TagName || '>%'
LEFT JOIN TopContributors tc ON qas.AnswerOwnerId = tc.UserId 
    AND tc.ReputationRank <= 100
LEFT JOIN InteractionPatterns ip ON qas.QuestionId = ip.PostId
WHERE tp.QuestionsInAnalysis >= 20
GROUP BY tp.TagName, tp.TagUsageCount, tp.AvgQuestionScore, tp.AvgViews, 
         tp.AvgAnswers, tp.MedianTimeToAnswer, tp.AcceptanceRate,
         tc.DisplayName, tc.Reputation, tc.AcceptedAnswerCount, 
         tc.AvgAnswerScore, tc.ReputationRank
HAVING COUNT(DISTINCT qas.QuestionId) >= 15
ORDER BY tp.AvgQuestionScore DESC, tp.AcceptanceRate DESC, tp.AvgViews DESC
LIMIT 100;
