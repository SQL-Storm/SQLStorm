WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        AVG(NULLIF(p.ViewCount, 0)) AS AvgViewCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        STRING_AGG(COALESCE(p.Tags, ''), '|' ) AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(p.Id) > 0 OR u.Reputation > 1000
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount,
        MAX(b.Date) AS LatestBadgeDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId
),
RecentActivity AS (
    SELECT 
        ph.UserId,
        MAX(ph.CreationDate) AS LastEditDate,
        (SELECT c.Text
         FROM Comments c
         WHERE c.UserId = ph.UserId
         ORDER BY c.CreationDate DESC
         LIMIT 1) AS LatestComment
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.UserId
),
CombinedStats AS (
    SELECT 
        us.UserId,
        us.Reputation,
        us.DisplayName,
        us.PostCount,
        us.TotalScore,
        us.AvgViewCount,
        us.ReputationRank,
        us.AllTags,
        COALESCE(bs.BadgeCount, 0) AS BadgeCount,
        bs.LatestBadgeDate,
        bs.GoldBadges,
        ra.LastEditDate,
        ra.LatestComment,
        CASE 
            WHEN us.Reputation > (SELECT AVG(u2.Reputation) FROM Users u2 WHERE u2.Reputation > 0) 
            THEN 'High Reputation' 
            ELSE 'Standard' 
        END AS ReputationCategory,
        COALESCE(
          UPPER(SUBSTRING(us.DisplayName FROM 1 FOR 1)) || LOWER(SUBSTRING(us.DisplayName FROM 2 FOR (CHAR_LENGTH(us.DisplayName) - 1))),
          'Anonymous'
        ) AS FormattedName
    FROM UserStats us
    FULL JOIN BadgeStats bs ON us.UserId = bs.UserId
    LEFT JOIN RecentActivity ra ON us.UserId = ra.UserId
    WHERE (us.ReputationRank IS NOT NULL AND us.ReputationRank <= 100) OR COALESCE(bs.GoldBadges, 0) > 5
)
SELECT 
    cs.UserId,
    cs.Reputation,
    cs.DisplayName,
    cs.PostCount,
    cs.TotalScore,
    cs.AvgViewCount,
    cs.ReputationRank,
    cs.AllTags,
    cs.BadgeCount,
    cs.LatestBadgeDate,
    cs.GoldBadges,
    cs.LastEditDate,
    cs.LatestComment,
    cs.ReputationCategory,
    cs.FormattedName,
    (SELECT COUNT(v.Id) 
     FROM Votes v 
     WHERE v.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = cs.UserId) 
       AND v.VoteTypeId = 2) AS UpvotesReceived
FROM CombinedStats cs

UNION ALL

SELECT 
    CAST(NULL AS BIGINT) AS UserId,
    AVG(Reputation) AS Reputation,
    'Average Stats' AS DisplayName,
    AVG(PostCount) AS PostCount,
    AVG(TotalScore) AS TotalScore,
    AVG(AvgViewCount) AS AvgViewCount,
    CAST(NULL AS BIGINT) AS ReputationRank,
    CAST(NULL AS TEXT) AS AllTags,
    AVG(BadgeCount) AS BadgeCount,
    CAST(NULL AS TIMESTAMP) AS LatestBadgeDate,
    AVG(GoldBadges) AS GoldBadges,
    CAST(NULL AS TIMESTAMP) AS LastEditDate,
    CAST(NULL AS TEXT) AS LatestComment,
    CAST(NULL AS TEXT) AS ReputationCategory,
    CAST(NULL AS TEXT) AS FormattedName,
    CAST(NULL AS BIGINT) AS UpvotesReceived
FROM CombinedStats

ORDER BY Reputation DESC;