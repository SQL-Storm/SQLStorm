-- {"query": "51092.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1277} 

WITH 
monthly_posts AS (
  SELECT 
    DATE_TRUNC('month', p.CreationDate) AS month,
    p.OwnerUserId,
    COUNT(*) AS post_count,
    AVG(p.Score) AS avg_score,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS positive_posts
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
  GROUP BY DATE_TRUNC('month', p.CreationDate), p.OwnerUserId
),
user_badges AS (
  SELECT 
    b.UserId,
    DATE_TRUNC('month', b.Date) AS month,
    COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges
  FROM Badges b
  WHERE b.Date >= CURRENT_DATE - INTERVAL '2 years'
  GROUP BY b.UserId, DATE_TRUNC('month', b.Date)
),
monthly_votes AS (
  SELECT 
    DATE_TRUNC('month', v.CreationDate) AS month,
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS downvotes
  FROM Votes v
  WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    AND v.VoteTypeId IN (2, 3)  -- Upvotes and downvotes only
  GROUP BY DATE_TRUNC('month', v.CreationDate), v.PostId
),
monthly_comments AS (
  SELECT 
    DATE_TRUNC('month', c.CreationDate) AS month,
    c.UserId,
    COUNT(*) AS comment_count,
    AVG(c.Score) AS avg_comment_score
  FROM Comments c
  WHERE c.CreationDate >= CURRENT_DATE - INTERVAL '2 years' AND c.UserId IS NOT NULL
  GROUP BY DATE_TRUNC('month', c.CreationDate), c.UserId
),
tag_popularity AS (
  SELECT 
    DATE_TRUNC('month', p.CreationDate) AS month,
    t.TagName,
    COUNT(*) AS tag_usage_count
  FROM Posts p
  CROSS JOIN LATERAL string_to_array(
    substring(p.Tags, 2, LENGTH(p.Tags) - 2), 
    '><'
  ) AS t(TagName)
  WHERE p.PostTypeId = 1 
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    AND p.Tags IS NOT NULL 
    AND LENGTH(p.Tags) > 2
  GROUP BY DATE_TRUNC('month', p.CreationDate), t.TagName
)
SELECT 
  mp.month,
  mp.OwnerUserId AS user_id,
  u.DisplayName AS user_name,
  u.Reputation AS user_reputation,
  mp.post_count,
  mp.avg_score,
  mp.positive_posts,
  COALESCE(ub.gold_badges, 0) AS gold_badges,
  COALESCE(ub.silver_badges, 0) AS silver_badges,
  COALESCE(ub.bronze_badges, 0) AS bronze_badges,
  COALESCE(mv.upvotes, 0) AS total_upvotes,
  COALESCE(mv.downvotes, 0) AS total_downvotes,
  COALESCE(mc.comment_count, 0) AS comments_made,
  COALESCE(mc.avg_comment_score, 0) AS avg_comment_score,
  COALESCE(tp.tag_usage_count, 0) AS popular_tag_usage,
  -- Calculate engagement ratio
  CASE 
    WHEN mp.post_count > 0 
    THEN ROUND(
      (COALESCE(mv.upvotes, 0) + COALESCE(mc.comment_count, 0) * 0.5)::numeric / 
      mp.post_count, 2
    )
    ELSE 0 
  END AS engagement_ratio,
  -- Rank users by monthly activity
  RANK() OVER (
    PARTITION BY mp.month 
    ORDER BY 
      mp.post_count DESC, 
      COALESCE(mv.upvotes, 0) DESC,
      u.Reputation DESC
  ) AS monthly_user_rank,
  -- Trending tag for the month
  (SELECT t2.TagName 
   FROM tag_popularity t2 
   WHERE t2.month = mp.month 
   ORDER BY t2.tag_usage_count DESC 
   LIMIT 1
  ) AS trending_tag
FROM monthly_posts mp
LEFT JOIN Users u ON mp.OwnerUserId = u.Id
LEFT JOIN user_badges ub ON mp.OwnerUserId = ub.UserId AND mp.month = ub.month
LEFT JOIN (
  SELECT 
    mv2.month,
    mp2.OwnerUserId,
    SUM(mv2.upvotes) AS upvotes,
    SUM(mv2.downvotes) AS downvotes
  FROM monthly_votes mv2
  JOIN Posts p2 ON mv2.PostId = p2.Id
  JOIN monthly_posts mp2 ON p2.OwnerUserId = mp2.OwnerUserId AND DATE_TRUNC('month', p2.CreationDate) = mv2.month
  GROUP BY mv2.month, mp2.OwnerUserId
) mv ON mp.OwnerUserId = mv.OwnerUserId AND mp.month = mv.month
LEFT JOIN monthly_comments mc ON mp.OwnerUserId = mc.UserId AND mp.month = mc.month
LEFT JOIN (
  SELECT 
    tp2.month,
    mp3.OwnerUserId,
    MAX(tp2.tag_usage_count) AS tag_usage_count
  FROM tag_popularity tp2
  JOIN monthly_posts mp3 ON tp2.month = mp3.month
  GROUP BY tp2.month, mp3.OwnerUserId
) tp ON mp.OwnerUserId = tp.OwnerUserId AND mp.month = tp.month
WHERE mp.post_count >= 1  -- Only active posters
ORDER BY mp.month DESC, monthly_user_rank ASC
LIMIT 1000;
