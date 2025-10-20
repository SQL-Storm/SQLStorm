-- {"query": "13006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 763} 

WITH UserReputationCTE AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionMetricsCTE AS (
    SELECT 
        p.Id AS QuestionId, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount,
        COALESCE(p.Tags, '') AS Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > CURRENT_DATE - INTERVAL '6 months'
),
TopQuestionsCTE AS (
    SELECT 
        QuestionId, 
        Title, 
        Score, 
        ViewCount, 
        AnswerCount,
        STRING_AGG(DISTINCT REGEXP_REPLACE(SPLIT_PART(value, '>', 1), '<', ''), ', ') AS CleanedTags
    FROM QuestionMetricsCTE
    CROSS JOIN LATERAL string_to_array(substring(Tags, 2, length(Tags) - 2), '><')
    WHERE rn <= 5
    GROUP BY QuestionId, Title, Score, ViewCount, AnswerCount
),
AnswerQualityCTE AS (
    SELECT 
        ParentId AS QuestionId, 
        COUNT(*) AS AnswerCount,
        AVG(Score) AS AvgAnswerScore,
        SUM(CASE WHEN Score >= 10 THEN 1 ELSE 0 END) AS HighQualityAnswers
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
)
SELECT 
    u.DisplayName, 
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    q.Title, 
    q.Score AS QuestionScore, 
    q.ViewCount,
    q.CleanedTags,
    a.AnswerCount, 
    a.AvgAnswerScore,
    a.HighQualityAnswers,
    (u.Reputation + COALESCE(u.GoldBadges, 0) * 10 + COALESCE(u.SilverBadges, 0) * 5 + COALESCE(u.BronzeBadges, 0)) * LOG(q.ViewCount + 1) AS UserImpactScore
FROM UserReputationCTE u
JOIN TopQuestionsCTE q ON u.Id = q.OwnerUserId
LEFT JOIN AnswerQualityCTE a ON q.QuestionId = a.QuestionId
WHERE u.Reputation > (SELECT AVG(Reputation) FROM UserReputationCTE)
ORDER BY UserImpactScore DESC
LIMIT 100;
