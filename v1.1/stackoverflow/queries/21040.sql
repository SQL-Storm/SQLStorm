WITH active_users AS (
    SELECT u.Id, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank,
           u.DisplayName,
           u.Location
    FROM Users u
    WHERE u.Reputation > 0
      AND u.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '1 year'
),
top_posts AS (
    SELECT p.Id, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount,
           p.CreationDate, p.OwnerUserId,
           COALESCE(p.LastEditDate, p.CreationDate) AS last_modified,
           LAG(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS prev_score,
           AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
      AND p.Score IS NOT NULL
      AND p.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '6 months'
),
user_activity AS (
    SELECT au.Id AS user_id,
           COUNT(DISTINCT tp.Id) AS posts_count,
           SUM(tp.ViewCount) AS total_views,
           AVG(tp.Score) AS avg_post_score,
           MAX(tp.last_modified) AS last_activity
    FROM active_users au
    LEFT JOIN top_posts tp ON au.Id = tp.OwnerUserId
    GROUP BY au.Id
    HAVING COUNT(DISTINCT tp.Id) > 0
),
badge_holders AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
           STRING_AGG(DISTINCT b.Name, '; ') AS badge_names
    FROM Badges b
    WHERE b.Date > CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY b.UserId
),
edited_posts AS (
    SELECT ph.PostId,
           COUNT(ph.Id) AS edit_count,
           MIN(ph.CreationDate) AS first_edit,
           CASE 
               WHEN COUNT(ph.Id) > 5 THEN 'heavily_edited'
               WHEN COUNT(ph.Id) BETWEEN 2 AND 5 THEN 'moderately_edited'
               ELSE 'lightly_edited'
           END AS edit_category
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '3 months'
    GROUP BY ph.PostId
)
SELECT 
    au.Id AS user_id,
    au.Reputation,
    au.rep_rank,
    COALESCE(ua.posts_count, 0) AS posts_count,
    COALESCE(ua.total_views, 0) AS total_views,
    ROUND(COALESCE(ua.avg_post_score, 0), 2) AS avg_post_score,
    ua.last_activity,
    COALESCE(bh.gold_badges, 0) AS gold_badges,
    COALESCE(bh.silver_badges, 0) AS silver_badges,
    COALESCE(bh.badge_names, 'none') AS badge_names,
    COALESCE(ep.edit_category, 'no_edits') AS edit_category,
    ep.edit_count,
    CASE 
        WHEN LENGTH(COALESCE(au.DisplayName, '')) > 15 
        THEN SUBSTRING(COALESCE(au.DisplayName, '') FROM 1 FOR 15) || '...'
        ELSE COALESCE(au.DisplayName, 'Anonymous')
    END AS short_display_name,
    GREATEST(0, COALESCE(ua.total_views, 0) / NULLIF(COALESCE(ua.posts_count, 0), 0)) AS views_per_post,
    RANK() OVER (ORDER BY COALESCE(ua.total_views, 0) DESC, au.Reputation DESC) AS activity_rank,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = au.Id 
       AND v.VoteTypeId IN (2, 3)
       AND v.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '1 month') AS recent_votes,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     WHERE pl.PostId IN (
         SELECT tp2.Id 
         FROM top_posts tp2 
         WHERE tp2.OwnerUserId = au.Id
     )
       AND pl.LinkTypeId = 1) AS external_links_created
FROM active_users au
LEFT JOIN user_activity ua ON au.Id = ua.user_id
LEFT JOIN badge_holders bh ON au.Id = bh.UserId
LEFT JOIN edited_posts ep ON ep.PostId = (
    SELECT MIN(tp3.Id) 
    FROM top_posts tp3 
    WHERE tp3.OwnerUserId = au.Id
)
WHERE au.rep_rank <= 1000
  AND (COALESCE(ua.posts_count, 0) > 0 OR COALESCE(bh.gold_badges, 0) > 0 OR COALESCE(ep.edit_count, 0) > 0)
  AND NOT (LOWER(au.Location) LIKE '%spam%' OR LOWER(au.DisplayName) LIKE '%bot%')
ORDER BY activity_rank, au.rep_rank
LIMIT 500;