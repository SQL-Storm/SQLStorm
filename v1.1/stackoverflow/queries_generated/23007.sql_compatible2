WITH UserActivityCTE AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY SUM(COALESCE(p.Score,0)) DESC) AS RankInLocation,
        STRING_AGG(COALESCE(p.Tags, ''), ', ') AS AllTags,
        u.Location
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 100
      AND (p.CreationDate > TIMESTAMP '2020-01-01' OR p.CreationDate IS NULL)
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
BadgeSummaryCTE AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
TopVotedPosts AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes,
        RANK() OVER (ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) DESC) AS VoteRank
    FROM Votes v
    WHERE v.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
    GROUP BY v.PostId
),
MainSet AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.TotalScore,
        ua.RankInLocation,
        UPPER(SUBSTRING(ua.AllTags FROM 1 FOR 50) || '...') AS TruncatedTags,
        COALESCE(bs.GoldBadges, 0) + COALESCE(bs.SilverBadges, 0) AS TotalBadges,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ua.UserId AND c.Score > 0) AS PositiveComments,
        tvp.NetVotes,
        CASE 
            WHEN ua.Reputation > 10000 THEN 'High Rep'
            WHEN ua.Reputation BETWEEN 1000 AND 10000 THEN 'Medium Rep'
            ELSE 'Low Rep'
        END AS RepCategory,
        LAG(ua.TotalScore) OVER (ORDER BY ua.Reputation DESC) AS PreviousScore
    FROM UserActivityCTE ua
    FULL JOIN BadgeSummaryCTE bs ON ua.UserId = bs.UserId
    LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId AND p.PostTypeId = 1
    INNER JOIN TopVotedPosts tvp ON p.Id = tvp.PostId
    WHERE (ua.RankInLocation IS NOT NULL AND ua.RankInLocation <= 10)
       OR (bs.LatestBadgeDate IS NOT NULL AND bs.LatestBadgeDate > TIMESTAMP '2023-01-01')
)
SELECT * FROM MainSet

UNION ALL

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS PostCount,
    0 AS TotalScore,
    CAST(NULL AS INTEGER) AS RankInLocation,
    '' AS TruncatedTags,
    0 AS TotalBadges,
    0 AS PositiveComments,
    0 AS NetVotes,
    'Inactive' AS RepCategory,
    CAST(NULL AS NUMERIC) AS PreviousScore
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.CreationDate < TIMESTAMP '2010-01-01'

UNION ALL

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    0 AS PostCount,
    0 AS TotalScore,
    CAST(NULL AS INTEGER) AS RankInLocation,
    '' AS TruncatedTags,
    COUNT(b.Id) AS TotalBadges,
    0 AS PositiveComments,
    0 AS NetVotes,
    'Badge Holder' AS RepCategory,
    CAST(NULL AS NUMERIC) AS PreviousScore
FROM Users u
INNER JOIN Badges b ON u.Id = b.UserId
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(b.Id) > 10

ORDER BY Reputation DESC;