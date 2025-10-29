-- {"query": "3879.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2160} 
-- Complex benchmark query using CTEs, window functions, outer joins, subqueries, string ops, and UNION
WITH TagPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- only questions
      AND p.Tags IS NOT NULL
),
UserAnswerStats AS (
    SELECT
        a.OwnerUserId,
        COUNT(*) FILTER (WHERE a.Score > 0)                AS PositiveAnswers,
        COUNT(*) FILTER (WHERE a.Score <= 0)               AS NonPositiveAnswers,
        SUM(a.Score)                                       AS TotalAnswerScore,
        AVG(a.Score)                                       AS AvgAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2                                -- only answers
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1)                AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2)                AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3)                AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
LatestPostCTE AS (
    SELECT
        p.OwnerUserId,
        p.Id               AS LatestPostId,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
)
SELECT
    u.Id                                   AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(uas.PositiveAnswers,0)        AS PositiveAnswers,
    COALESCE(uas.NonPositiveAnswers,0)     AS NonPositiveAnswers,
    COALESCE(uas.TotalAnswerScore,0)       AS TotalAnswerScore,
    COALESCE(ubc.GoldBadges,0)              AS GoldBadges,
    COALESCE(ubc.SilverBadges,0)            AS SilverBadges,
    COALESCE(ubc.BronzeBadges,0)            AS BronzeBadges,
    lp.LatestPostId,
    lp.CreationDate                        AS LatestPostDate,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    CASE
        WHEN COALESCE(uas.TotalAnswerScore,0) = 0 THEN NULL
        ELSE ROUND(100.0 * COALESCE(uas.PositiveAnswers,0) /
                   NULLIF(uas.TotalAnswerScore,0), 2)
    END                                    AS PositiveScorePct,
    STRING_AGG(DISTINCT tp.Tag, ',') FILTER (WHERE tp.Tag IS NOT NULL) AS TagsAnswered
FROM Users u
LEFT JOIN UserAnswerStats   uas ON uas.OwnerUserId = u.Id
LEFT JOIN UserBadgeCounts   ubc ON ubc.UserId = u.Id
LEFT JOIN LatestPostCTE     lp  ON lp.OwnerUserId = u.Id AND lp.rn = 1
LEFT JOIN TagPosts          tp  ON tp.OwnerUserId = u.Id
WHERE u.Reputation > 10000
GROUP BY
    u.Id, u.DisplayName, u.Reputation,
    uas.PositiveAnswers, uas.NonPositiveAnswers, uas.TotalAnswerScore,
    ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges,
    lp.LatestPostId, lp.CreationDate

UNION ALL

SELECT
    NULL                                   AS UserId,
    'TOTAL'                                AS DisplayName,
    SUM(u.Reputation)                      AS Reputation,
    SUM(COALESCE(uas.PositiveAnswers,0))   AS PositiveAnswers,
    SUM(COALESCE(uas.NonPositiveAnswers,0))AS NonPositiveAnswers,
    SUM(COALESCE(uas.TotalAnswerScore,0))  AS TotalAnswerScore,
    SUM(COALESCE(ubc.GoldBadges,0))         AS GoldBadges,
    SUM(COALESCE(ubc.SilverBadges,0))       AS SilverBadges,
    SUM(COALESCE(ubc.BronzeBadges,0))       AS BronzeBadges,
    NULL                                   AS LatestPostId,
    NULL                                   AS LatestPostDate,
    NULL                                   AS ReputationRank,
    NULL                                   AS PositiveScorePct,
    NULL                                   AS TagsAnswered
FROM Users u
LEFT JOIN UserAnswerStats   uas ON uas.OwnerUserId = u.Id
LEFT JOIN UserBadgeCounts   ubc ON ubc.UserId = u.Id
WHERE u.Reputation > 10000;