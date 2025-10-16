-- {"query": "16038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 91065, "output_tokens": 84523} 

WITH RECURSIVE user_activity_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS net_votes,
    EXTRACT(YEAR FROM u.CreationDate) AS join_year,
    CASE 
      WHEN u.Reputation > 10000 THEN 'Elite'
      WHEN u.Reputation > 1000 THEN 'Expert'
      WHEN u.Reputation > 100 THEN 'Intermediate'
      ELSE 'Beginner'
    END AS user_tier
  FROM Users u
  WHERE u.CreationDate >= '2020-01-01'
),
post_quality_analysis AS (
  SELECT 
    p.Id AS post_id,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    COALESCE(p.FavoriteCount, 0) AS favorites,
    LENGTH(COALESCE(p.Body, '')) AS body_length,
    CASE 
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
      ELSE 0
    END AS has_accepted_answer,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS user_post_rank,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS avg_user_score,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC NULLS LAST) AS view_rank,
    LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_date,
    LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2021-01-01'
),
badge_distribution AS (
  SELECT 
    b.UserId,
    COUNT(*) AS total_badges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
    STRING_AGG(DISTINCT SUBSTRING(b.Name, 1, 20), '|' ORDER BY b.Name) AS badge_names,
    MAX(b.Date) AS latest_badge_date
  FROM Badges b
  GROUP BY b.UserId
  HAVING COUNT(*) > 5
),
comment_engagement AS (
  SELECT 
    c.PostId,
    COUNT(DISTINCT c.UserId) AS unique_commenters,
    AVG(c.Score) AS avg_comment_score,
    MAX(LENGTH(c.Text)) AS max_comment_length,
    COUNT(*) FILTER (WHERE c.Score > 5) AS high_scored_comments
  FROM Comments c
  WHERE c.CreationDate >= '2021-06-01'
  GROUP BY c.PostId
),
vote_patterns AS (
  SELECT 
    v.PostId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS favorites,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS bounties_started,
    SUM(COALESCE(v.BountyAmount, 0)) AS total_bounty_amount,
    ARRAY_AGG(DISTINCT v.VoteTypeId ORDER BY v.VoteTypeId) AS vote_type_array
  FROM Votes v
  GROUP BY v.PostId
)
SELECT 
  uam.DisplayName,
  uam.user_tier,
  uam.Reputation,
  uam.net_votes,
  pqa.post_id,
  pqa.Score AS post_score,
  pqa.avg_user_score,
  pqa.view_rank,
  COALESCE(bd.total_badges, 0) AS total_badges,
  COALESCE(bd.gold_badges, 0) AS gold_count,
  CONCAT(COALESCE(SUBSTRING(bd.badge_names, 1, 50), 'None'), 
         CASE WHEN LENGTH(COALESCE(bd.badge_names, '')) > 50 THEN '...' ELSE '' END) AS truncated_badges,
  COALESCE(ce.unique_commenters, 0) AS comment_users,
  COALESCE(ce.avg_comment_score, 0.0) AS avg_comment_score,
  COALESCE(vp.upvotes, 0) - COALESCE(vp.downvotes, 0) AS net_post_votes,
  COALESCE(vp.total_bounty_amount, 0) AS bounty_total,
  CASE 
    WHEN pqa.next_post_score > pqa.Score THEN 'Improving'
    WHEN pqa.next_post_score < pqa.Score THEN 'Declining'
    WHEN pqa.next_post_score IS NULL THEN 'Latest'
    ELSE 'Stable'
  END AS score_trend,
  CASE 
    WHEN pqa.prev_post_date IS NOT NULL 
    THEN EXTRACT(EPOCH FROM (pqa.prev_post_date - uam.CreationDate)) / 86400.0
    ELSE NULL
  END AS days_since_prev_post,
  (SELECT COUNT(*) 
   FROM PostLinks pl 
   WHERE pl.PostId = pqa.post_id AND pl.LinkTypeId = 3) AS duplicate_count,
  (SELECT COUNT(DISTINCT ph.UserId)
   FROM PostHistory ph
   WHERE ph.PostId = pqa.post_id 
     AND ph.PostHistoryTypeId IN (4, 5, 6)
     AND ph.UserId IS NOT NULL) AS distinct_editors,
  CASE 
    WHEN pqa.body_length > 5000 THEN 'Very Long'
    WHEN pqa.body_length > 1000 THEN 'Long'
    WHEN pqa.body_length > 200 THEN 'Medium'
    ELSE 'Short'
  END AS content_length_category,
  ROUND(pqa.Score::numeric / NULLIF(COALESCE(pqa.ViewCount, 1), 0) * 100, 2) AS score_per_view_ratio
FROM user_activity_metrics uam
INNER JOIN post_quality_analysis pqa ON uam.Id = pqa.OwnerUserId
LEFT OUTER JOIN badge_distribution bd ON uam.Id = bd.UserId
LEFT OUTER JOIN comment_engagement ce ON pqa.post_id = ce.PostId
LEFT OUTER JOIN vote_patterns vp ON pqa.post_id = vp.PostId
WHERE pqa.user_post_rank <= 10
  AND (pqa.Score > 5 OR pqa.has_accepted_answer = 1)
  AND (bd.total_badges IS NULL OR bd.total_badges > 3)
  AND uam.Reputation > 500
  AND NOT EXISTS (
    SELECT 1 
    FROM Posts p2 
    WHERE p2.OwnerUserId = uam.Id 
      AND p2.ClosedDate IS NOT NULL 
      AND p2.Score < -5
  )
ORDER BY 
  uam.Reputation DESC,
  pqa.view_rank ASC,
  COALESCE(vp.total_bounty_amount, 0) DESC,
  pqa.Score DESC
LIMIT 500;
