-- {"query": "21011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1181} 

WITH RecentPosts AS (
    SELECT p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
           u.Reputation, u.UpVotes, u.DownVotes,
           ROW_NUMBER() OVER (PARTITION BY COALESCE(p.OwnerUserId, -1) ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
      AND (p.Score > 0 OR p.ViewCount > 1000)
),
ActiveUsers AS (
    SELECT UserId, COUNT(*) as post_count,
           AVG(Score) as avg_score,
           STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LEAST(20, LENGTH(p.Tags)-2)), ', ') as top_tags
    FROM RecentPosts rp
    JOIN Posts p ON rp.Id = p.Id
    WHERE rp.rn <= 5
    GROUP BY UserId
    HAVING COUNT(*) >= 3
),
BadgeStats AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as silver_badges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as bronze_badges,
           COUNT(*) as total_badges
    FROM Badges b
    WHERE b.Date >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY b.UserId
),
VoteSummary AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId IN (2) THEN 1 ELSE 0 END) as up_votes,
           SUM(CASE WHEN v.VoteTypeId IN (3) THEN -1 ELSE 0 END) as down_votes,
           SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) as accepted_count,
           MAX(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as max_bounty
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY v.PostId
)
SELECT 
    rp.Id as post_id,
    COALESCE(au.post_count, 0) as recent_posts,
    au.avg_score,
    au.top_tags,
    COALESCE(bs.total_badges, 0) as total_badges,
    COALESCE(bs.gold_badges, 0) as gold_badges,
    vs.up_votes + COALESCE(vs.accepted_count, 0) as net_positive_votes,
    CASE 
        WHEN au.avg_score IS NULL THEN 'Low Activity'
        WHEN au.avg_score > 50 AND bs.gold_badges >= 1 THEN 'Elite'
        WHEN au.post_count >= 10 OR (vs.max_bounty > 0 AND rp.Score > 100) THEN 'High Impact'
        ELSE 'Standard'
    END as user_category,
    LENGTH(COALESCE(au.top_tags, '')) + COALESCE(vs.up_votes, 0) as complexity_score,
    GREATEST(rp.ViewCount / NULLIF(rp.Score, 0), 1) as views_per_score,
    rp.Reputation * (1.0 + (COALESCE(bs.total_badges, 0) / 10.0)) as weighted_reputation
FROM RecentPosts rp
LEFT JOIN ActiveUsers au ON rp.OwnerUserId = au.UserId
LEFT JOIN BadgeStats bs ON rp.OwnerUserId = bs.UserId
LEFT JOIN VoteSummary vs ON rp.Id = vs.PostId
WHERE rp.rn <= 3
  AND (rp.Reputation > 1000 
       OR EXISTS (SELECT 1 FROM Posts linked WHERE linked.ParentId = rp.Id AND linked.Score > 0)
       OR rp.ViewCount > (SELECT AVG(ViewCount) * 2 FROM Posts WHERE PostTypeId = 1 AND CreationDate >= CURRENT_DATE - INTERVAL '1 year'))
UNION ALL
SELECT 
    NULL as post_id,
    SUM(COALESCE(au.post_count, 0)) as recent_posts,
    AVG(COALESCE(au.avg_score, 0)) as avg_score,
    STRING_AGG(DISTINCT SUBSTRING(COALESCE(au.top_tags, ''), 1, 50), ' | ') as top_tags,
    SUM(COALESCE(bs.total_badges, 0)) as total_badges,
    SUM(COALESCE(bs.gold_badges, 0)) as gold_badges,
    SUM(COALESCE(vs.up_votes + COALESCE(vs.accepted_count, 0), 0)) as net_positive_votes,
    'OVERALL' as user_category,
    SUM(LENGTH(COALESCE(au.top_tags, '')) + COALESCE(vs.up_votes, 0)) as complexity_score,
    AVG(GREATEST(rp.ViewCount / NULLIF(rp.Score, 0), 1)) as views_per_score,
    SUM(rp.Reputation * (1.0 + (COALESCE(bs.total_badges, 0) / 10.0))) as weighted_reputation
FROM RecentPosts rp
LEFT JOIN ActiveUsers au ON rp.OwnerUserId = au.UserId
LEFT JOIN BadgeStats bs ON rp.OwnerUserId = bs.UserId
LEFT JOIN VoteSummary vs ON rp.Id = vs.PostId
WHERE rp.rn <= 3
ORDER BY complexity_score DESC, weighted_reputation DESC
LIMIT 100;
