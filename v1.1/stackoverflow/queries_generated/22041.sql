-- {"query": "22041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1200} 
WITH UserAnswerStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS TotalAnswers,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgAnswerScore,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1,2,3,4,5,6,7,8,9) THEN 1 ELSE 0 END) AS EditCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 2  -- Answers
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        SUM(b.Class) AS BadgeScore
    FROM Badges b
    GROUP BY b.UserId
),
UserCommentStats AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    GROUP BY c.UserId
),
RankedUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(uas.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(uas.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(uas.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(uas.EditCount, 0) AS EditCount,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ubs.BadgeScore, 0) AS BadgeScore,
        COALESCE(ucs.TotalComments, 0) AS TotalComments,
        COALESCE(ucs.AvgCommentLength, 0) AS AvgCommentLength,
        (u.Reputation + COALESCE(uas.TotalAnswerScore, 0) + (COALESCE(ubs.BadgeScore, 0) * 100) + COALESCE(ucs.TotalComments, 0)) / NULLIF(COALESCE(uas.TotalAnswers, 0) + 1, 0) AS CustomScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(uas.TotalAnswerScore, 0) DESC) AS OverallRank,
        RANK() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 10) ORDER BY COALESCE(ubs.GoldBadges, 0) DESC, u.Reputation DESC) AS LocationBadgeRank
    FROM Users u
    LEFT OUTER JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
    LEFT OUTER JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    LEFT OUTER JOIN UserCommentStats ucs ON u.Id = ucs.UserId
    WHERE u.Reputation > 1000
    AND COALESCE(uas.TotalAnswers, 0) > 0
    AND EXISTS (
        SELECT 1
        FROM Posts p_inner
        WHERE p_inner.OwnerUserId = u.Id
        AND p_inner.PostTypeId = 1
        AND p_inner.CreationDate >= '2010-01-01'
    )
)
SELECT 
    ru.Id,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalAnswers,
    ru.TotalAnswerScore,
    ru.AvgAnswerScore,
    ru.EditCount,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.BadgeScore,
    ru.TotalComments,
    ru.AvgCommentLength,
    ru.CustomScore,
    ru.OverallRank,
    ru.LocationBadgeRank,
    CASE 
        WHEN ru.CustomScore > 10000 THEN 'Elite'
        WHEN ru.CustomScore BETWEEN 5000 AND 10000 THEN 'Advanced'
        WHEN ru.CustomScore BETWEEN 1000 AND 4999 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserLevel,
    CONCAT('User: ', ru.DisplayName, ' from ', COALESCE(SUBSTRING((SELECT Location FROM Users WHERE Id = ru.Id), 1, 20), 'Unknown')) AS UserDescription
FROM RankedUsers ru
WHERE ru.TotalAnswers > (SELECT AVG(TotalAnswers) FROM RankedUsers WHERE OverallRank <= 100)
UNION ALL
SELECT 
    NULL AS Id,
    'Aggregate' AS DisplayName,
    SUM(Reputation) AS Reputation,
    AVG(TotalAnswers) AS TotalAnswers,
    SUM(TotalAnswerScore) AS TotalAnswerScore,
    AVG(AvgAnswerScore) AS AvgAnswerScore,
    SUM(EditCount) AS EditCount,
    SUM(GoldBadges) AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges,
    SUM(BadgeScore) AS BadgeScore,
    SUM(TotalComments) AS TotalComments,
    AVG(AvgCommentLength) AS AvgCommentLength,
    AVG(CustomScore) AS CustomScore,
    NULL AS OverallRank,
    NULL AS LocationBadgeRank,
    'Aggregate' AS UserLevel,
    'Summary of Top Users' AS UserDescription
FROM RankedUsers
ORDER BY OverallRank ASC NULLS LAST, CustomScore DESC;