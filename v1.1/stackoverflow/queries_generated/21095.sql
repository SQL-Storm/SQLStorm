-- {"query": "21095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1034} 

WITH active_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rep_rank
  FROM Users u
  WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
    AND u.Reputation > 100
),
influential_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate,
         au.DisplayName as author_name,
         LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
         (p.ViewCount * 1.0 / NULLIF(p.CreationDate - au.active_since, 0)) as views_per_day
  FROM Posts p
  INNER JOIN active_users au ON p.OwnerUserId = au.Id
  WHERE p.PostTypeId = 1  -- Questions only
    AND p.Score > 0
    AND p.ClosedDate IS NULL
  QUALIFY views_per_day > 10  -- Top performers
),
tagged_questions AS (
  SELECT ip.Id, ip.Title, ip.Score,
         CASE 
           WHEN ip.Tags LIKE '%sql%' THEN 'SQL Heavy'
           WHEN ip.Tags LIKE '%python%' THEN 'Python Heavy'
           ELSE 'Other'
         END as tag_category,
         LENGTH(COALESCE(ip.Title, '')) + 
         (SELECT COUNT(*) FROM PostHistory ph 
          WHERE ph.PostId = ip.Id AND ph.PostHistoryTypeId IN (4,5,6)  -- Edits
          AND ph.CreationDate > ip.CreationDate - INTERVAL '30 days') as complexity_score
  FROM influential_posts ip
  WHERE ip.Tags IS NOT NULL 
    AND LENGTH(ip.Tags) > 10
),
vote_insights AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as upvote_count,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) as downvote_count,
         AVG(v.CreationDate) as avg_vote_time
  FROM Votes v
  WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    AND v.VoteTypeId IN (2,3)  -- Up/Down votes
  GROUP BY v.PostId
  HAVING upvote_count + downvote_count > 5
)
SELECT 
  tq.tag_category,
  COUNT(*) as question_count,
  ROUND(AVG(tq.score), 2) as avg_score,
  ROUND(AVG(tq.complexity_score), 2) as avg_complexity,
  MAX(tq.score) as max_score,
  COUNT(DISTINCT vi.PostId) as posts_with_votes,
  (SELECT STRING_AGG(DISTINCT b.Name, ', ') 
   FROM Badges b 
   INNER JOIN active_users au2 ON b.UserId = au2.Id 
   WHERE b.Date >= CURRENT_DATE - INTERVAL '30 days' 
     AND b.Class = 1  -- Gold badges only
     AND au2.rep_rank <= 50
  ) as recent_top_badges,
  COALESCE(
    (SELECT AVG(vs.score) 
     FROM (
       SELECT p.Score as score, 
              ROW_NUMBER() OVER (PARTITION BY LEFT(p.Tags, 10) ORDER BY p.Score DESC) as rn
       FROM Posts p 
       WHERE p.PostTypeId = 1 AND p.Tags LIKE '%' || tq.tag_category || '%'
     ) vs 
     WHERE vs.rn <= 3
    ), 0
  ) as top3_avg_per_category
FROM tagged_questions tq
FULL OUTER JOIN vote_insights vi ON tq.Id = vi.PostId
LEFT JOIN Tags tg ON tq.Title ILIKE '%' || tg.TagName || '%'
WHERE (tq.complexity_score > 15 OR vi.upvote_count IS NULL)
  AND (tg.Count > 100 OR tg.Count IS NULL)
GROUP BY tq.tag_category
HAVING COUNT(*) >= 3
UNION ALL
SELECT 'Uncategorized' as tag_category,
       COUNT(*) as question_count,
       ROUND(AVG(tq.score), 2) as avg_score,
       ROUND(AVG(tq.complexity_score), 2) as avg_complexity,
       MAX(tq.score) as max_score,
       0 as posts_with_votes,
       NULL as recent_top_badges,
       0 as top3_avg_per_category
FROM tagged_questions tq
WHERE tq.tag_category = 'Other'
  AND NOT EXISTS (
    SELECT 1 FROM PostLinks pl 
    INNER JOIN Posts rp ON pl.RelatedPostId = rp.Id 
    WHERE pl.PostId = tq.Id 
      AND pl.LinkTypeId = 3  -- Duplicates
      AND rp.ClosedDate IS NOT NULL
  )
ORDER BY avg_score DESC
LIMIT 10;
