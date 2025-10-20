-- {"query": "28011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1788} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RepRank,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY v.UserId) AS TotalUpvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.CreationDate > CURRENT_DATE - INTERVAL '1 year') AS RecentComments
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2,3,8)
    GROUP BY u.Id, u.Location, u.Reputation, v.UserId
), PostAnalysis AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseEvents,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '; ') AS AllTags,
        AVG(p.Score * 1.0 / NULLIF(p.ViewCount, 0)) AS EngagementRatio,
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
        (SELECT Id FROM Posts p2 WHERE p2.OwnerUserId = us.Id)) AS DuplicatePosts
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
    CONCAT(u.DisplayName, ' (Inactive)'),
    u.Location,
    NULL,
    NULL,
    9999,
    'Inactive',
    (SELECT COUNT(*) FROM Posts p4 
     WHERE p4.OwnerUserId = u.Id AND p4.CreationDate < CURRENT_DATE - INTERVAL '2 years')
FROM Users u
WHERE u.LastAccessDate < CURRENT_DATE - INTERVAL '1 year'
  AND NOT EXISTS (SELECT 1 FROM UserStats us WHERE us.Id = u.Id)
ORDER BY GlobalRank ASC, UserTier DESC;
