WITH UserReputationCTE AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT CASE WHEN b."class" = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b."class" = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b."class" = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionMetricsCTE AS (
    SELECT 
        p.Id AS QuestionId, 
        p.OwnerUserId,
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount,
        COALESCE(p.Tags, '') AS Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '6 months'
),
TopQuestionsCTE AS (
    SELECT 
        qm.QuestionId, 
        qm.OwnerUserId,
        qm.Title, 
        qm.Score, 
        qm.ViewCount, 
        qm.AnswerCount,
        STRING_AGG(DISTINCT REPLACE(SPLIT_PART(tag, '>', 1), '<', ''), ', ') AS CleanedTags
    FROM QuestionMetricsCTE qm
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(SUBSTRING(qm.Tags FROM 2 FOR GREATEST(LENGTH(qm.Tags) - 2, 0)), '><')) AS tag
    ) t
    WHERE qm.rn <= 5
    GROUP BY qm.QuestionId, qm.OwnerUserId, qm.Title, qm.Score, qm.ViewCount, qm.AnswerCount
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
FETCH FIRST 100 ROWS ONLY;