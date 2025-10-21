-- {"query": "21064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1675} 

WITH RecentPosts AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.OwnerUserId,
         u.Reputation, u.DisplayName AS OwnerName,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 
    AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    AND p.Score > 0
),
ActiveUsers AS (
  SELECT UserId, COUNT(*) AS post_count,
         SUM(CASE WHEN Score >= 5 THEN 1 ELSE 0 END) AS high_score_posts
  FROM RecentPosts
  WHERE rn <= 5
  GROUP BY UserId
  HAVING COUNT(*) >= 3
),
PostStats AS (
  SELECT rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.AnswerCount,
         rp.OwnerUserId, rp.Reputation, rp.OwnerName,
         au.post_count, au.high_score_posts,
         COALESCE(v.up_votes, 0) AS up_votes,
         COALESCE(v.down_votes, 0) AS down_votes,
         COALESCE(c.comment_count, 0) AS comment_count,
         LAG(rp.Score) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate) AS prev_score,
         FIRST_VALUE(rp.Title) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.ViewCount DESC 
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS most_viewed_title
  FROM RecentPosts rp
  INNER JOIN ActiveUsers au ON rp.OwnerUserId = au.UserId
  LEFT JOIN (
    SELECT PostId, 
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes
    WHERE VoteTypeId IN (2, 3)
    GROUP BY PostId
  ) v ON rp.Id = v.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS comment_count
    FROM Comments
    WHERE Score > 0
    GROUP BY PostId
  ) c ON rp.Id = c.PostId
),
TagAnalysis AS (
  SELECT DISTINCT p.Id AS post_id,
         UNNEST(STRING_TO_ARRAY(
           SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), 
           '><'
         )) AS tag_name,
         ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY t.Count DESC) AS tag_rank
  FROM Posts p
  INNER JOIN Tags t ON POSITION(LOWER(t.TagName) IN LOWER(p.Tags)) > 0
  WHERE p.PostTypeId = 1 
    AND p.Tags IS NOT NULL 
    AND LENGTH(p.Tags) > 4
    AND t.Count > 10
),
BadgeStats AS (
  SELECT b.UserId,
         COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
         COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
         COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
         STRING_AGG(DISTINCT b.Name, ', ') AS badge_names
  FROM Badges b
  WHERE b.Date >= CURRENT_DATE - INTERVAL '2 years'
  GROUP BY b.UserId
)
SELECT 
  ps.Id AS post_id,
  ps.Title,
  ps.CreationDate,
  ps.Score,
  ps.ViewCount,
  ps.AnswerCount,
  ps.OwnerUserId,
  ps.OwnerName,
  ps.Reputation,
  ps.post_count,
  ps.high_score_posts,
  ps.up_votes,
  ps.down_votes,
  ps.comment_count,
  (ps.Score - COALESCE(ps.prev_score, 0)) AS score_improvement,
  CASE 
    WHEN ps.ViewCount > 1000 THEN 'High Traffic'
    WHEN ps.ViewCount > 100 THEN 'Moderate Traffic'
    ELSE 'Low Traffic'
  END AS traffic_category,
  ta.tag_name,
  bs.gold_badges,
  bs.silver_badges,
  bs.bronze_badges,
  LENGTH(COALESCE(ps.Title, '')) + LENGTH(COALESCE(ta.tag_name, '')) AS title_tag_length,
  CASE 
    WHEN ps.post_count >= 10 AND ps.high_score_posts >= 3 THEN 'Power User'
    WHEN ps.Reputation > 5000 THEN 'Expert'
    WHEN ps.Reputation > 1000 THEN 'Active'
    ELSE 'Newcomer'
  END AS user_tier,
  -- Complex NULL logic with COALESCE chains
  COALESCE(
    NULLIF(ps.most_viewed_title, ps.Title),
    ps.Title,
    'Untitled'
  ) AS featured_title,
  -- String manipulation for title analysis
  UPPER(SUBSTRING(ps.Title FROM 1 FOR 1)) || 
  LOWER(SUBSTRING(ps.Title FROM 2)) AS title_normalized,
  -- Date calculations
  EXTRACT(DAY FROM AGE(CURRENT_DATE, ps.CreationDate)) AS days_since_creation,
  -- Window function for ranking within user
  RANK() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.ViewCount DESC) AS view_rank,
  -- Correlated subquery for average score comparison
  (SELECT AVG(p2.Score) 
   FROM Posts p2 
   WHERE p2.OwnerUserId = ps.OwnerUserId 
     AND p2.PostTypeId = 1 
     AND p2.CreationDate < ps.CreationDate) AS avg_prev_score
FROM PostStats ps
LEFT JOIN TagAnalysis ta ON ps.Id = ta.post_id AND ta.tag_rank = 1
LEFT JOIN BadgeStats bs ON ps.OwnerUserId = bs.UserId
WHERE (ps.ViewCount > 500 OR ps.AnswerCount > 5)
  AND (ps.Title ILIKE '%sql%' OR ta.tag_name ILIKE '%database%' OR ta.tag_name IS NULL)
  AND NOT EXISTS (
    SELECT 1 FROM PostHistory ph 
    WHERE ph.PostId = ps.Id 
      AND ph.PostHistoryTypeId = 12  -- Deleted
      AND ph.CreationDate > ps.CreationDate
  )
  AND (ps.Reputation > 100 OR ps.post_count > 5)
UNION ALL
SELECT 
  NULL AS post_id,
  'SUMMARY ROW' AS Title,
  CURRENT_DATE AS CreationDate,
  SUM(ps.Score) AS Score,
  SUM(ps.ViewCount) AS ViewCount,
  SUM(ps.AnswerCount) AS AnswerCount,
  NULL AS OwnerUserId,
  'AGGREGATE' AS OwnerName,
  AVG(ps.Reputation) AS Reputation,
  SUM(ps.post_count) AS post_count,
  SUM(ps.high_score_posts) AS high_score_posts,
  SUM(ps.up_votes) AS up_votes,
  SUM(ps.down_votes) AS down_votes,
  SUM(ps.comment_count) AS comment_count,
  NULL AS score_improvement,
  NULL AS traffic_category,
  NULL AS tag_name,
  SUM(bs.gold_badges) AS gold_badges,
  SUM(bs.silver_badges) AS silver_badges,
  SUM(bs.bronze_badges) AS bronze_badges,
  NULL AS title_tag_length,
  NULL AS user_tier,
  NULL AS featured_title,
  NULL AS title_normalized,
  NULL AS days_since_creation,
  NULL AS view_rank,
  NULL AS avg_prev_score
FROM PostStats ps
LEFT JOIN BadgeStats bs ON ps.OwnerUserId = bs.UserId
ORDER BY 
  CASE WHEN post_id IS NULL THEN 0 ELSE 1 END,
  COALESCE(ps.Reputation, 0) DESC,
  ps.ViewCount DESC
LIMIT 1000;
