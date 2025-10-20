WITH 
top_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
  FROM Users u 
  WHERE u.Reputation > 1000
),
top_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.OwnerUserId, p.Tags,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS post_rank
  FROM Posts p 
  WHERE p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 100
),
high_activity_posts AS (
  SELECT p.Id, p.Score, p.CommentCount, p.FavoriteCount,
         AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS avg_bounty,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvote_count,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvote_count,
         p.ViewCount
  FROM Posts p 
  LEFT JOIN Votes v ON p.Id = v.PostId 
  WHERE p.PostTypeId = 1 AND p.CommentCount > 5 AND p.FavoriteCount > 10
  GROUP BY p.Id, p.Score, p.CommentCount, p.FavoriteCount, p.ViewCount
  HAVING COUNT(v.Id) > 20
),
tag_usage AS (
  SELECT t.Id AS tag_id, t.TagName, 
         COUNT(p.Id) AS question_count,
         AVG(p.Score) AS avg_score,
         PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.ViewCount) AS p90_views
  FROM Tags t 
  JOIN Posts p ON POSITION(t.TagName IN p.Tags) > 0
  WHERE p.PostTypeId = 1 AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
  GROUP BY t.Id, t.TagName
  HAVING COUNT(p.Id) > 50
),
recent_edits AS (
  SELECT ph.PostId, COUNT(ph.Id) AS edit_count,
         AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate))/3600) AS avg_hours_to_edit,
         STRING_AGG(DISTINCT ph.UserDisplayName, ', ') AS editors
  FROM PostHistory ph 
  JOIN Posts p ON ph.PostId = p.Id
  WHERE ph.PostHistoryTypeId IN (4,5,6)
    AND ph.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
    AND p.PostTypeId = 1
  GROUP BY ph.PostId, p.CreationDate
),
duplicate_networks AS (
  SELECT pl.RelatedPostId AS root_id, 
         COUNT(DISTINCT pl.PostId) AS duplicate_count,
         ARRAY_AGG(DISTINCT pl.PostId ORDER BY pl.PostId) AS dup_posts
  FROM PostLinks pl 
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name = 'Duplicate'
  GROUP BY pl.RelatedPostId
  HAVING COUNT(DISTINCT pl.PostId) > 3
),
badge_leaders AS (
  SELECT b.UserId, 
         COUNT(b.Id) AS total_badges,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_count,
         ARRAY_AGG(DISTINCT b.Name ORDER BY b.Name) AS badge_names
  FROM Badges b 
  JOIN top_users tu ON b.UserId = tu.Id
  WHERE b.Date > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years')
  GROUP BY b.UserId
  HAVING COUNT(b.Id) > 10
),
median_high_activity_views AS (
  SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ViewCount) AS median_high_activity_views
  FROM high_activity_posts
)
SELECT 
  tu.DisplayName AS top_user,
  tp.Title AS top_post_title,
  hap.avg_bounty,
  hap.upvote_count - hap.downvote_count AS net_votes,
  tu2.tag_id,
  tu2.TagName,
  re.edit_count,
  COALESCE(dn.duplicate_count, 0) AS duplicates,
  bl.total_badges,
  bl.gold_count,
  ROW_NUMBER() OVER (ORDER BY hap.upvote_count DESC, tu.Reputation DESC) AS overall_rank,
  m.median_high_activity_views
FROM top_users tu
JOIN top_posts tp ON tu.Id = tp.OwnerUserId AND tp.post_rank <= 5
JOIN high_activity_posts hap ON tp.Id = hap.Id
LEFT JOIN tag_usage tu2 ON POSITION(tu2.TagName IN tp.Tags) > 0 
LEFT JOIN recent_edits re ON hap.Id = re.PostId
LEFT JOIN duplicate_networks dn ON tp.Id = dn.root_id
LEFT JOIN badge_leaders bl ON tu.Id = bl.UserId
CROSS JOIN median_high_activity_views m
WHERE tu.rep_rank <= 100
  AND tp.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
  AND (hap.avg_bounty IS NULL OR hap.avg_bounty > 50)
ORDER BY overall_rank
LIMIT 50;