-- {"query": "51072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1067} 

WITH 
top_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rep_rank
  FROM Users u 
  WHERE u.Reputation > 1000
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.OwnerUserId,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) as post_rank
  FROM Posts p 
  WHERE p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 100
),
high_activity_posts AS (
  SELECT p.Id, p.Score, p.CommentCount, p.FavoriteCount,
         AVG(v.BountyAmount) OVER (PARTITION BY p.Id) as avg_bounty,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvote_count,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvote_count
  FROM Posts p 
  LEFT JOIN Votes v ON p.Id = v.PostId 
  WHERE p.PostTypeId = 1 AND p.CommentCount > 5 AND p.FavoriteCount > 10
  GROUP BY p.Id, p.Score, p.CommentCount, p.FavoriteCount
  HAVING COUNT(v.Id) > 20
),
tag_usage AS (
  SELECT t.Id as tag_id, t.TagName, 
         COUNT(p.Id) as question_count,
         AVG(p.Score) as avg_score,
         PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.ViewCount) as p90_views
  FROM Tags t 
  JOIN Posts p ON position(t.TagName in p.Tags) > 0
  WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '1 year'
  GROUP BY t.Id, t.TagName
  HAVING COUNT(p.Id) > 50
),
recent_edits AS (
  SELECT ph.PostId, COUNT(ph.Id) as edit_count,
         AVG(EXTRACT(EPOCH FROM (ph.CreationDate - ph.PostId::Posts.CreationDate))/3600) as avg_hours_to_edit,
         STRING_AGG(DISTINCT ph.UserDisplayName, ', ') as editors
  FROM PostHistory ph 
  JOIN Posts p ON ph.PostId = p.Id
  WHERE ph.PostHistoryTypeId IN (4,5,6)  -- Edits
    AND ph.CreationDate > NOW() - INTERVAL '6 months'
    AND p.PostTypeId = 1
  GROUP BY ph.PostId
),
duplicate_networks AS (
  SELECT pl.RelatedPostId as root_id, 
         COUNT(DISTINCT pl.PostId) as duplicate_count,
         ARRAY_AGG(DISTINCT pl.PostId ORDER BY pl.PostId) as dup_posts
  FROM PostLinks pl 
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name = 'Duplicate'
  GROUP BY pl.RelatedPostId
  HAVING COUNT(DISTINCT pl.PostId) > 3
),
badge_leaders AS (
  SELECT b.UserId, 
         COUNT(b.Id) as total_badges,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_count,
         ARRAY_AGG(DISTINCT b.Name ORDER BY b.Name) as badge_names
  FROM Badges b 
  JOIN top_users tu ON b.UserId = tu.Id
  WHERE b.Date > NOW() - INTERVAL '2 years'
  GROUP BY b.UserId
  HAVING COUNT(b.Id) > 10
)
SELECT 
  tu.DisplayName as top_user,
  tp.Title as top_post_title,
  hap.avg_bounty,
  hap.upvote_count - hap.downvote_count as net_votes,
  tu.tag_id, tu.TagName,
  re.edit_count,
  COALESCE(dn.duplicate_count, 0) as duplicates,
  bl.total_badges,
  bl.gold_count,
  ROW_NUMBER() OVER (ORDER BY hap.upvote_count DESC, tu.Reputation DESC) as overall_rank,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY hap.ViewCount) OVER () as median_high_activity_views
FROM top_users tu
JOIN top_posts tp ON tu.Id = tp.OwnerUserId AND tp.post_rank <= 5
JOIN high_activity_posts hap ON tp.Id = hap.Id
LEFT JOIN tag_usage tu2 ON position(tu2.TagName in tp.Tags) > 0 
LEFT JOIN recent_edits re ON hap.Id = re.PostId
LEFT JOIN duplicate_networks dn ON tp.Id = dn.root_id
LEFT JOIN badge_leaders bl ON tu.Id = bl.UserId
WHERE tu.rep_rank <= 100
  AND tp.CreationDate > NOW() - INTERVAL '1 year'
  AND (hap.avg_bounty IS NULL OR hap.avg_bounty > 50)
ORDER BY overall_rank
LIMIT 50;
