-- {"query": "21004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1025} 

WITH active_users AS (
    SELECT u.Id, u.Reputation, u.CreationDate,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rep_rank
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
),
question_stats AS (
    SELECT p.Id as post_id, p.OwnerUserId,
           COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as upvote_count,
           COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as downvote_count,
           AVG(v.CreationDate::date - p.CreationDate::date) as avg_days_to_vote,
           STRING_AGG(DISTINCT SUBSTRING(pl.RelatedPostId::text FROM 1 FOR 4), ',') as linked_post_snippets
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 1
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CURRENT_DATE - INTERVAL '5 years'
      AND p.Score > 0
    GROUP BY p.Id, p.OwnerUserId
    HAVING COUNT(v.Id) > 5 OR p.ViewCount > 10000
),
badge_richness AS (
    SELECT b.UserId,
           COUNT(*) as total_badges,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
           MAX(b.Date) as latest_badge_date
    FROM Badges b
    GROUP BY b.UserId
),
complex_posts AS (
    SELECT qs.post_id, qs.OwnerUserId, qs.upvote_count,
           COALESCE(br.total_badges, 0) as badge_bonus,
           CASE 
               WHEN qs.upvote_count > 50 THEN 'High Impact'
               WHEN qs.upvote_count > 10 THEN 'Moderate Impact'
               ELSE 'Low Impact'
           END as impact_category,
           LAG(qs.upvote_count) OVER (PARTITION BY qs.OwnerUserId ORDER BY p.CreationDate) as prev_post_upvotes,
           (qs.upvote_count - COALESCE(LAG(qs.upvote_count) OVER (PARTITION BY qs.OwnerUserId ORDER BY p.CreationDate), 0)) as upvote_growth
    FROM question_stats qs
    INNER JOIN Posts p ON p.Id = qs.post_id
    LEFT JOIN badge_richness br ON br.UserId = qs.OwnerUserId
    WHERE (qs.upvote_count + COALESCE(br.gold_badges, 0) * 10) > 20
)
SELECT au.DisplayName as user_name,
       au.rep_rank,
       cp.impact_category,
       cp.upvote_count + (cp.badge_bonus * 2) as weighted_score,
       cp.upvote_growth,
       cp.linked_post_snippets,
       CASE 
           WHEN cp.latest_badge_date IS NULL THEN 'No Recent Badges'
           WHEN cp.latest_badge_date > CURRENT_DATE - INTERVAL '6 months' THEN 'Active Badge Earner'
           ELSE 'Stale Achievements'
       END as badge_status,
       (SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.PostId = cp.post_id 
          AND (c.Text ILIKE '%great%' OR c.Text ILIKE '%helpful%') 
          AND c.Score >= 0) as positive_comment_count
FROM complex_posts cp
INNER JOIN active_users au ON au.Id = cp.OwnerUserId
LEFT JOIN Badges b ON b.UserId = au.Id 
    AND b.Date = (SELECT MAX(Date) FROM Badges WHERE UserId = au.Id)
WHERE au.rep_rank <= 100
  AND (cp.upvote_growth > 0 OR cp.upvote_count > 100)
  AND NOT EXISTS (
      SELECT 1 FROM PostHistory ph 
      WHERE ph.PostId = cp.post_id 
        AND ph.PostHistoryTypeId = 12  -- Deleted
        AND ph.CreationDate > p.CreationDate - INTERVAL '1 month'
  )
UNION ALL
SELECT 'Aggregate Top Performers' as user_name,
       0 as rep_rank,
       'Overall Leaderboard' as impact_category,
       SUM(cp.weighted_score) as weighted_score,
       AVG(cp.upvote_growth) as upvote_growth,
       STRING_AGG(DISTINCT COALESCE(cp.linked_post_snippets, ''), '; ') as linked_post_snippets,
       'Community Aggregate' as badge_status,
       SUM(cp.positive_comment_count) as positive_comment_count
FROM complex_posts cp
WHERE cp.OwnerUserId IN (
    SELECT au.Id FROM active_users au WHERE au.rep_rank <= 10
)
ORDER BY weighted_score DESC NULLS LAST
LIMIT 50;
