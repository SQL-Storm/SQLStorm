WITH active_users AS (
    SELECT u.Id, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
    FROM Users u
    WHERE u.Reputation > 0
      AND u.CreationDate > (DATE '2024-10-01' - INTERVAL '1' YEAR)
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
      AND p.CreationDate > (DATE '2024-10-01' - INTERVAL '6' MONTH)
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
           COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
           STRING_AGG(DISTINCT b.Name, '; ') AS badge_names
    FROM Badges b
    WHERE b.Date > (DATE '2024-10-01' - INTERVAL '1' YEAR)
    GROUP BY b.UserId
),
edited_posts AS (
    SELECT DISTINCT ph.PostId,
           COUNT(ph.Id) AS edit_count,
           MIN(ph.CreationDate) AS first_edit,
           CASE 
               WHEN COUNT(ph.Id) > 5 THEN 'heavily_edited'
               WHEN COUNT(ph.Id) BETWEEN 2 AND 5 THEN 'moderately_edited'
               ELSE 'lightly_edited'
           END AS edit_category
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.CreationDate > (DATE '2024-10-01' - INTERVAL '3' MONTH)
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
        WHEN LENGTH(COALESCE(ua_display_name.au_display_name, '')) > 15 
        THEN SUBSTR(ua_display_name.au_display_name, 1, 15) || '...'
        ELSE COALESCE(ua_display_name.au_display_name, 'Anonymous')
    END AS short_display_name,
    GREATEST(0, COALESCE(ua.total_views, 0) / NULLIF(COALESCE(ua.posts_count, 0), 0)) AS views_per_post,
    RANK() OVER (ORDER BY COALESCE(ua.total_views, 0) DESC, au.Reputation DESC) AS activity_rank,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = au.Id 
       AND v.VoteTypeId IN (2, 3)
       AND v.CreationDate > (DATE '2024-10-01' - INTERVAL '1' MONTH)) AS recent_votes,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     WHERE pl.PostId IN (
         SELECT tp.Id 
         FROM top_posts tp 
         WHERE tp.OwnerUserId = au.Id
     )
       AND pl.LinkTypeId = 1) AS external_links_created
FROM active_users au
LEFT JOIN user_activity ua ON au.Id = ua.user_id
LEFT JOIN badge_holders bh ON au.Id = bh.UserId
LEFT JOIN edited_posts ep ON ep.PostId IN (
    SELECT tp.Id 
    FROM top_posts tp 
    WHERE tp.OwnerUserId = au.Id
)
LEFT JOIN (
    SELECT u.Id AS au_display_user_id, u.DisplayName AS au_display_name
    FROM Users u
) AS ua_display_name ON au.Id = ua_display_name.au_display_user_id
WHERE au.rep_rank <= 1000
  AND (ua.posts_count > 0 OR bh.gold_badges > 0 OR ep.edit_count > 0)
  AND NOT (LOWER(ua_display_name.au_display_name) LIKE '%spam%' OR LOWER(ua_display_name.au_display_name) LIKE '%bot%')
ORDER BY activity_rank, au.rep_rank
LIMIT 500;