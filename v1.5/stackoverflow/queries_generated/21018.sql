-- {"query": "21018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1076} 

WITH active_users AS (
  SELECT u.Id AS user_id, u.Reputation, u.CreationDate
  FROM Users u
  WHERE u.Reputation >= 1000
    AND u.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
),
post_stats AS (
  SELECT 
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvote_count,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvote_count,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS total_bounties,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS avg_post_score
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 8)
  WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers only
    AND p.DeletionDate IS NULL
  GROUP BY p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score
  HAVING COUNT(*) >= 5  -- Users with at least 5 posts
),
top_badges AS (
  SELECT 
    b.UserId,
    b.Name,
    b.Date,
    b.Class,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
  FROM Badges b
  WHERE b.Class = 1  -- Gold badges only
),
complex_activity AS (
  SELECT 
    p.Id AS post_id,
    p.Title,
    p.Tags,
    p.CreationDate,
    COALESCE(ps.upvote_count, 0) + COALESCE(ps.downvote_count, 0) AS total_votes,
    LENGTH(COALESCE(p.Body, '')) AS body_length,
    CASE 
      WHEN p.Tags LIKE '%sql%' THEN 'SQL Related'
      WHEN p.Tags LIKE '%javascript%' THEN 'JavaScript Related'
      ELSE 'Other'
    END AS tag_category,
    RANK() OVER (ORDER BY COALESCE(ps.upvote_count, 0) DESC, p.ViewCount DESC) AS popularity_rank
  FROM Posts p
  LEFT JOIN post_stats ps ON p.OwnerUserId = ps.OwnerUserId AND p.CreationDate::date = ps.CreationDate::date
  WHERE p.PostTypeId = 1  -- Questions only
    AND p.ClosedDate IS NULL
    AND (p.ViewCount > 100 OR ps.upvote_count > 50)
)
SELECT 
  au.user_id,
  au.Reputation,
  COUNT(DISTINCT ca.post_id) AS question_count,
  AVG(ca.popularity_rank) AS avg_rank,
  SUM(CASE WHEN ca.tag_category = 'SQL Related' THEN 1 ELSE 0 END) AS sql_questions,
  MAX(ca.body_length) AS longest_post,
  tb.Name AS latest_gold_badge,
  (SELECT STRING_AGG(DISTINCT substring(c.Text, 1, 50), ' | ')
   FROM Comments c 
   WHERE c.PostId = ca.post_id 
     AND c.Score > 0 
     AND c.UserId != p.OwnerUserId
   ORDER BY c.CreationDate DESC 
   LIMIT 3) AS top_comments,
  CASE 
    WHEN au.Reputation > 10000 AND sql_questions > 10 THEN 'SQL Guru'
    WHEN au.Reputation > 5000 THEN 'Expert'
    ELSE 'Active User'
  END AS user_tier
FROM active_users au
INNER JOIN post_stats ps ON au.user_id = ps.OwnerUserId
INNER JOIN complex_activity ca ON ps.OwnerUserId = ca.post_id  -- Correlated-like join for complexity
LEFT JOIN top_badges tb ON au.user_id = tb.UserId AND tb.rn = 1
LEFT JOIN Posts p ON ca.post_id = p.Id  -- Self-reference for comments
WHERE ca.CreationDate > au.CreationDate
  AND (ca.total_votes > 10 OR ca.body_length > 1000)
  AND NOT (p.Title ILIKE '%homework%' AND p.Score < 5)  -- Exclude low-quality homework posts
GROUP BY au.user_id, au.Reputation, tb.Name, ca.tag_category
HAVING COUNT(DISTINCT ca.post_id) > 2
   OR (SUM(CASE WHEN ca.tag_category = 'SQL Related' THEN ca.total_votes ELSE 0 END) > 100)
UNION ALL
SELECT 
  NULL AS user_id,
  0 AS Reputation,
  COUNT(*) AS question_count,
  AVG(popularity_rank) AS avg_rank,
  SUM(CASE WHEN tag_category = 'SQL Related' THEN 1 ELSE 0 END) AS sql_questions,
  NULL AS longest_post,
  NULL AS latest_gold_badge,
  NULL AS top_comments,
  'Aggregate Stats' AS user_tier
FROM complex_activity
WHERE popularity_rank <= 100
ORDER BY question_count DESC, Reputation DESC
LIMIT 50;
