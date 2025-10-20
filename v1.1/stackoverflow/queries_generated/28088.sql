-- {"query": "28088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1447} 

WITH UserBadgeStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
PostActivity AS (
    SELECT
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        COALESCE(p.ClosedDate, p.LastEditDate, p.LastActivityDate) AS LastModified
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, POSITION('>' IN p.Tags) - 2), ', ') AS FirstTags,
    AVG(pa.Score) FILTER (WHERE pa.PostTypeId = 1) OVER (PARTITION BY u.Id) AS AvgQuestionScore,
    COUNT(DISTINCT pa.CreationDate) AS ActiveDays,
    (SELECT MAX(Score) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2) AS MaxAnswerScore,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM Comments c 
            WHERE c.UserId = u.Id 
            AND c.CreationDate BETWEEN u.CreationDate AND u.LastAccessDate
        ) THEN 1 ELSE 0 
    END AS HasComments,
    COALESCE((
        SELECT SUM(v.BountyAmount) 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId = 8
    ), 0) AS TotalBounty,
    RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank
FROM Users u
LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN PostActivity pa ON u.Id = pa.OwnerUserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
WHERE u.Reputation > 1000
    AND u.Id IN (
        SELECT UserId 
        FROM Badges 
        WHERE Date > (SELECT MAX(CreationDate) FROM Posts WHERE OwnerUserId = Badges.UserId)
    )
    AND (u.AboutMe IS NOT NULL OR ubs.LastBadgeDate > '2020-01-01')
GROUP BY u.Id, u.DisplayName, u.Reputation, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges
HAVING COUNT(pa.PostRank) > 5
UNION ALL
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    0, 0, 0,
    NULL,
    0,
    0,
    0,
    0,
    0,
    RANK() OVER (ORDER BY u.Reputation DESC)
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
ORDER BY GlobalRank, TotalBounty DESC;
