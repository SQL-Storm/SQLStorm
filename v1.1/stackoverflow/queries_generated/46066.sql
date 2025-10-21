-- {"query": "46066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1577}

WITH TopQuestionAuthors AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.OwnerUserId IS NOT NULL
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT p.Id) >= 5
),
AnswerMetrics AS (
    SELECT 
        a.OwnerUserId as AnswererId,
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        q.OwnerUserId as QuestionOwnerId,
        q.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    WHERE a.PostTypeId = 2 
        AND q.PostTypeId = 1
        AND a.OwnerUserId IS NOT NULL
        AND a.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '18 months'
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
        COUNT(DISTINCT v.Id) as VotesCast,
        COUNT(DISTINCT c.Id) as CommentCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '3 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count as TagUsageCount,
        COUNT(DISTINCT p.Id) as RecentQuestions,
        AVG(p.Score) as AvgQuestionScore,
        AVG(p.AnswerCount) as AvgAnswerCount,
        SUM(p.ViewCount) as TotalTagViews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
        AND t.Count > 100
    GROUP BY t.TagName, t.Count
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.BadgeCount,
    ue.GoldBadges,
    ue.SilverBadges,
    tqa.QuestionCount,
    tqa.AvgScore as AvgQuestionScore,
    tqa.TotalViews,
    COUNT(DISTINCT am.AnswerId) as AnswersGiven,
    COUNT(DISTINCT CASE WHEN am.AnswerRank = 1 THEN am.AnswerId END) as TopRankedAnswers,
    COUNT(DISTINCT CASE WHEN am.AcceptedAnswerId = am.AnswerId THEN am.AnswerId END) as AcceptedAnswers,
    AVG(am.AnswerScore) as AvgAnswerScore,
    ue.VotesCast,
    ue.CommentCount,
    STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.TagName) as TopTags,
    AVG(tp.AvgQuestionScore) as AvgTagScore,
    ROUND(
        (tqa.QuestionCount * 2.0 + 
         COUNT(DISTINCT am.AnswerId) * 1.5 + 
         COUNT(DISTINCT CASE WHEN am.AcceptedAnswerId = am.AnswerId THEN am.AnswerId END) * 3.0 + 
         ue.GoldBadges * 5.0 + 
         ue.SilverBadges * 2.0) / 
        NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MIN(am.AnswerDate))) / 86400.0, 0),
        4
    ) as EngagementScorePerDay
FROM UserEngagement ue
JOIN TopQuestionAuthors tqa ON ue.UserId = tqa.OwnerUserId
LEFT JOIN AnswerMetrics am ON ue.UserId = am.AnswererId
LEFT JOIN Posts p ON p.OwnerUserId = ue.UserId AND p.PostTypeId = 1
LEFT JOIN TagPerformance tp ON p.Tags LIKE '%<' || tp.TagName || '>%'
WHERE tqa.QuestionCount >= 5
    AND ue.Reputation > 1000
GROUP BY 
    ue.DisplayName,
    ue.Reputation,
    ue.BadgeCount,
    ue.GoldBadges,
    ue.SilverBadges,
    tqa.QuestionCount,
    tqa.AvgScore,
    tqa.TotalViews,
    ue.VotesCast,
    ue.CommentCount
HAVING COUNT(DISTINCT am.AnswerId) >= 3
ORDER BY EngagementScorePerDay DESC NULLS LAST, ue.Reputation DESC
LIMIT 100;
