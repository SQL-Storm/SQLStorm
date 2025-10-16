WITH BadgesSummary AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
PostMetrics AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        p.Id
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 OR p.PostTypeId = 2
    GROUP BY p.OwnerUserId, p.Id, p.Score
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(bs.GoldBadges, 0) + COALESCE(bs.SilverBadges, 0) + COALESCE(bs.BronzeBadges, 0) AS TotalBadges,
    pm.TotalComments,
    (pm.Upvotes - pm.Downvotes) AS NetVotes,
    RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
    DENSE_RANK() OVER (PARTITION BY CASE 
        WHEN COALESCE(bs.GoldBadges,0) >= 5 THEN 'Elite' 
        WHEN COALESCE(bs.SilverBadges,0) >= 10 THEN 'Active' 
        ELSE 'Standard' 
    END ORDER BY u.Reputation DESC) AS CategoryRank,
    CASE WHEN EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
          AND ph.PostHistoryTypeId IN (10, 11, 12) 
          AND ph.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
    ) THEN TRUE ELSE FALSE END AS HasModerationHistory,
    STRING_AGG(DISTINCT t.TagName, '; ') FILTER (WHERE t.IsModeratorOnly = TRUE) AS ModeratorTags,
    CASE 
        WHEN (u.LastAccessDate IS NOT NULL AND u.CreationDate IS NOT NULL AND u.LastAccessDate > u.CreationDate + INTERVAL '5 years') THEN 'Veteran' 
        WHEN u.Reputation > 100000 THEN 'Legend' 
        ELSE 'Regular' 
    END AS UserClass,
    COUNT(DISTINCT p.Id) AS PostCount
FROM Users u
LEFT JOIN BadgesSummary bs ON u.Id = bs.UserId
LEFT JOIN PostMetrics pm ON u.Id = pm.OwnerUserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
WHERE u.Reputation > 1000
    AND (pm.LastPostDate > DATE '2022-01-01' OR pm.LastPostDate IS NULL)
    AND (bs.LastBadgeDate > DATE '2021-01-01' OR bs.LastBadgeDate IS NULL)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges,
    pm.TotalComments, pm.Upvotes, pm.Downvotes, u.LastAccessDate, u.CreationDate,
    pm.OwnerUserId, pm.LastPostDate, pm.AvgPostScore, u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 10 OR COUNT(DISTINCT p.Id) = 0
ORDER BY TotalBadges DESC, NetVotes DESC
LIMIT 100;