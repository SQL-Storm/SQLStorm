WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS RepRank,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate > (DATE '2024-10-01' - INTERVAL '1' YEAR)) AS RecentComments
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2,3,8)
    GROUP BY u.Id, u.DisplayName, u.Location, u.Reputation
), PostAnalysis AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseEvents,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '; ') AS AllTags,
        AVG(CASE WHEN p.ViewCount = 0 THEN NULL ELSE (CAST(p.Score AS DECIMAL) / NULLIF(p.ViewCount,0)) END) AS EngagementRatio,
        MAX(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS EverClosed
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
)
SELECT 
    us.DisplayName,
    us.Location,
    pa.AllTags,
    (us.TotalUpvotes - COALESCE(SUM(v.BountyAmount), 0)) * 1.0 / NULLIF(us.GoldBadges, 0) AS EngagementScore,
    RANK() OVER (ORDER BY pa.EngagementRatio DESC) AS GlobalRank,
    CASE 
        WHEN pa.EverClosed = 1 THEN 'Controversial'
        WHEN us.GoldBadges > 5 THEN 'Elite'
        WHEN us.RecentComments > 100 THEN 'Active'
        ELSE 'Regular'
    END AS UserTier,
    (SELECT COUNT(*) FROM PostLinks pl 
     WHERE pl.LinkTypeId = 3 AND pl.PostId IN 
        (SELECT Id FROM Posts p2 WHERE p2.OwnerUserId = us.Id)) AS DuplicatePosts,
    us.Id
FROM UserStats us
JOIN PostAnalysis pa ON us.Id = pa.OwnerUserId
LEFT JOIN Votes v ON us.Id = v.UserId AND v.VoteTypeId = 8
WHERE us.RepRank <= 10
  AND us.Location <> 'Unknown'
  AND pa.CloseEvents < 5
  AND us.GoldBadges + (SELECT COUNT(*) FROM Posts p3 
                       WHERE p3.OwnerUserId = us.Id AND p3.AnswerCount > 10) > 3
GROUP BY us.DisplayName, us.Location, pa.AllTags, us.TotalUpvotes, 
         us.GoldBadges, pa.EngagementRatio, pa.EverClosed, us.RecentComments, us.Id
HAVING SUM(CASE WHEN v.BountyAmount > 50 THEN 1 ELSE 0 END) > 0

UNION ALL

SELECT 
    (u.DisplayName || ' (Inactive)') AS displayname,
    u.Location,
    NULL AS AllTags,
    NULL AS EngagementScore,
    9999 AS GlobalRank,
    'Inactive' AS UserTier,
    (SELECT COUNT(*) FROM Posts p4 
     WHERE p4.OwnerUserId = u.Id AND p4.CreationDate < (DATE '2024-10-01' - INTERVAL '2' YEAR)) AS DuplicatePosts,
    u.Id
FROM Users u
WHERE u.LastAccessDate < (DATE '2024-10-01' - INTERVAL '1' YEAR)
  AND NOT EXISTS (SELECT 1 FROM UserStats us WHERE us.Id = u.Id)

ORDER BY GlobalRank ASC, UserTier DESC;