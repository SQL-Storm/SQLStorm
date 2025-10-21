-- {"query": "21040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1124} 

WITH active_users AS (
    SELECT u.Id, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rep_rank
    FROM Users u
    WHERE u.Reputation > 0
      AND u.CreationDate > CURRENT_DATE - INTERVAL '1 year'
),
top_posts AS (
    SELECT p.Id, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount,
           p.CreationDate, p.OwnerUserId,
           COALESCE(p.LastEditDate, p.CreationDate) as last_modified,
           LAG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) as prev_score,
           AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as avg_score_by_type
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.Score IS NOT NULL
      AND p.CreationDate > CURRENT_DATE - INTERVAL '6 months'
),
user_activity AS (
    SELECT au.Id as user_id,
           COUNT(DISTINCT tp.Id) as posts_count,
           SUM(tp.ViewCount) as total_views,
           AVG(tp.Score) as avg_post_score,
           MAX(tp.last_modified) as last_activity
    FROM active_users au
    LEFT JOIN top_posts tp ON au.Id = tp.OwnerUserId
    GROUP BY au.Id
    HAVING COUNT(DISTINCT tp.Id) > 0
),
badge_holders AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE b.Class = 1) as gold_badges,
           COUNT(*) FILTER (WHERE b.Class = 2) as silver_badges,
           STRING_AGG(DISTINCT b.Name, '; ') as badge_names
    FROM Badges b
    WHERE b.Date > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY b.UserId
),
edited_posts AS (
    SELECT DISTINCT ph.PostId,
           COUNT(ph.Id) as edit_count,
           MIN(ph.CreationDate) as first_edit,
           CASE 
               WHEN COUNT(ph.Id) > 5 THEN 'heavily_edited'
               WHEN COUNT(ph.Id) BETWEEN 2 AND 5 THEN 'moderately_edited'
               ELSE 'lightly_edited'
           END as edit_category
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)  -- Title, Body, Tags edits
      AND ph.CreationDate > CURRENT_DATE - INTERVAL '3 months'
    GROUP BY ph.PostId
)
SELECT 
    au.Id as user_id,
    au.Reputation,
    au.rep_rank,
    COALESCE(ua.posts_count, 0) as posts_count,
    COALESCE(ua.total_views, 0) as total_views,
    ROUND(COALESCE(ua.avg_post_score, 0)::numeric, 2) as avg_post_score,
    ua.last_activity,
    COALESCE(bh.gold_badges, 0) as gold_badges,
    COALESCE(bh.silver_badges, 0) as silver_badges,
    COALESCE(bh.badge_names, 'none') as badge_names,
    COALESCE(ep.edit_category, 'no_edits') as edit_category,
    ep.edit_count,
    -- Complex string manipulation
    CASE 
        WHEN LENGTH(COALESCE(au.DisplayName, '')) > 15 
        THEN LEFT(au.DisplayName, 15) || '...'
        ELSE COALESCE(au.DisplayName, 'Anonymous')
    END as short_display_name,
    -- NULL-safe calculations
    GREATEST(0, COALESCE(ua.total_views, 0) / NULLIF(COALESCE(ua.posts_count, 0), 0)) as views_per_post,
    -- Window function for ranking within the result set
    RANK() OVER (ORDER BY COALESCE(ua.total_views, 0) DESC, au.Reputation DESC) as activity_rank,
    -- Set operation simulation within CTEs
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = au.Id 
       AND v.VoteTypeId IN (2, 3)  -- Up/Down votes
       AND v.CreationDate > CURRENT_DATE - INTERVAL '1 month') as recent_votes,
    -- Correlated subquery for linked content
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     WHERE pl.PostId IN (
         SELECT tp.Id 
         FROM top_posts tp 
         WHERE tp.OwnerUserId = au.Id
     )
       AND pl.LinkTypeId = 1) as external_links_created
FROM active_users au
LEFT OUTER JOIN user_activity ua ON au.Id = ua.user_id
LEFT OUTER JOIN badge_holders bh ON au.Id = bh.UserId
LEFT OUTER JOIN edited_posts ep ON ep.PostId IN (
    SELECT tp.Id 
    FROM top_posts tp 
    WHERE tp.OwnerUserId = au.Id
)
WHERE au.rep_rank <= 1000  -- Top 1000 users by reputation
  AND (ua.posts_count > 0 OR bh.gold_badges > 0 OR ep.edit_count > 0)  -- Active in some way
  AND NOT (au.Location ILIKE '%spam%' OR au.DisplayName ILIKE '%bot%')  -- Basic filtering
ORDER BY activity_rank, au.rep_rank
LIMIT 500;
