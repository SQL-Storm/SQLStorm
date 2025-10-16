WITH RecentPosts AS (
    SELECT p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
           u.Reputation, u.UpVotes, u.DownVotes,
           ROW_NUMBER() OVER (PARTITION BY COALESCE(p.OwnerUserId, -1) ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR
      AND (p.Score > 0 OR p.ViewCount > 1000)
),
ActiveUsers AS (
    SELECT rp.OwnerUserId AS UserId,
           COUNT(*) as post_count,
           AVG(rp.Score) as avg_score,
           STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR LEAST(20, (LENGTH(p.Tags) - 2))), ', ') as top_tags
    FROM RecentPosts rp
    JOIN Posts p ON rp.Id = p.Id
    WHERE rp.rn <= 5
    GROUP BY rp.OwnerUserId
    HAVING COUNT(*) >= 3
),
BadgeStats AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as silver_badges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as bronze_badges,
           COUNT(*) as total_badges
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01' AS DATE) - INTERVAL '2' YEAR
    GROUP BY b.UserId
),
VoteSummary AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as up_votes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) as down_votes,
           SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) as accepted_count,
           MAX(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount,0) ELSE 0 END) as max_bounty
    FROM Votes v
    WHERE v.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR
    GROUP BY v.PostId
)
SELECT 
    rp.Id as post_id,
    COALESCE(au.post_count, 0) as recent_posts,
    au.avg_score,
    au.top_tags,
    COALESCE(bs.total_badges, 0) as total_badges,
    COALESCE(bs.gold_badges, 0) as gold_badges,
    COALESCE(vs.up_votes,0) + COALESCE(vs.accepted_count, 0) as net_positive_votes,
    CASE 
        WHEN au.avg_score IS NULL THEN 'Low Activity'
        WHEN au.avg_score > 50 AND COALESCE(bs.gold_badges,0) >= 1 THEN 'Elite'
        WHEN COALESCE(au.post_count,0) >= 10 OR (COALESCE(vs.max_bounty,0) > 0 AND rp.Score > 100) THEN 'High Impact'
        ELSE 'Standard'
    END as user_category,
    LENGTH(COALESCE(au.top_tags, '')) + COALESCE(vs.up_votes, 0) as complexity_score,
    GREATEST(CASE WHEN rp.Score = 0 THEN 1.0 ELSE CAST(rp.ViewCount AS DECIMAL) / NULLIF(rp.Score,0) END, 1) as views_per_score,
    rp.Reputation * (1.0 + (COALESCE(bs.total_badges, 0) / 10.0)) as weighted_reputation
FROM RecentPosts rp
LEFT JOIN ActiveUsers au ON rp.OwnerUserId = au.UserId
LEFT JOIN BadgeStats bs ON rp.OwnerUserId = bs.UserId
LEFT JOIN VoteSummary vs ON rp.Id = vs.PostId
WHERE rp.rn <= 3
  AND (rp.Reputation > 1000 
       OR EXISTS (SELECT 1 FROM Posts linked WHERE linked.ParentId = rp.Id AND linked.Score > 0)
       OR rp.ViewCount > (SELECT AVG(ViewCount) * 2 FROM Posts WHERE PostTypeId = 1 AND CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR))
UNION ALL
SELECT 
    CAST(NULL AS INTEGER) as post_id,
    SUM(COALESCE(au.post_count, 0)) as recent_posts,
    AVG(COALESCE(au.avg_score, 0)) as avg_score,
    STRING_AGG(DISTINCT SUBSTRING(COALESCE(au.top_tags, '') FROM 1 FOR 50), ' | ') as top_tags,
    SUM(COALESCE(bs.total_badges, 0)) as total_badges,
    SUM(COALESCE(bs.gold_badges, 0)) as gold_badges,
    SUM(COALESCE(vs.up_votes, 0) + COALESCE(vs.accepted_count, 0)) as net_positive_votes,
    'OVERALL' as user_category,
    SUM(LENGTH(COALESCE(au.top_tags, '')) + COALESCE(vs.up_votes, 0)) as complexity_score,
    AVG(GREATEST(CASE WHEN rp.Score = 0 THEN 1.0 ELSE CAST(rp.ViewCount AS DECIMAL) / NULLIF(rp.Score,0) END, 1)) as views_per_score,
    SUM(rp.Reputation * (1.0 + (COALESCE(bs.total_badges, 0) / 10.0))) as weighted_reputation
FROM RecentPosts rp
LEFT JOIN ActiveUsers au ON rp.OwnerUserId = au.UserId
LEFT JOIN BadgeStats bs ON rp.OwnerUserId = bs.UserId
LEFT JOIN VoteSummary vs ON rp.Id = vs.PostId
WHERE rp.rn <= 3
GROUP BY CAST(NULL AS INTEGER)
ORDER BY complexity_score DESC, weighted_reputation DESC
LIMIT 100;