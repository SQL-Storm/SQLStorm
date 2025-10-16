WITH user_activity AS (
    SELECT 
        u.Id AS user_id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS user_creation,
        COUNT(DISTINCT p.Id) AS post_count,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        COUNT(DISTINCT c.Id) AS comment_count,
        MAX(ph.CreationDate) AS last_edit,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS score_rank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.UserId = u.Id
    WHERE u.Reputation > 100
      AND u.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1' YEAR)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) >= 5
),
badge_summary AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS badge_count,
        -- Portable string aggregation using STRING_AGG (Postgres) or LISTAGG (Oracle)
        -- Use STRING_AGG for portability; cast ordering expression to text if needed.
        COALESCE(STRING_AGG(b.Name, '; ' ORDER BY b.Date DESC), '') AS badge_names,
        MAX(b.Date) AS latest_badge_date
    FROM Badges b
    JOIN user_activity ua ON ua.user_id = b.UserId
    WHERE b.Class IN (1, 2)
    GROUP BY b.UserId, b.Class
),
post_engagement AS (
    SELECT 
        p.Id AS post_id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS post_date,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS answer_count,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS post_status,
        -- approximate tag complexity: count of tags by counting '<' occurrences if tags are in <tag> format
        (LENGTH(COALESCE(p.Tags, '')) - LENGTH(REPLACE(COALESCE(p.Tags, ''), '<', ''))) AS tag_complexity
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Score > 0
      AND (p.ClosedDate IS NULL OR p.ClosedDate > (CAST('2024-10-01' AS date) - INTERVAL '6' MONTH))
),
linked_posts AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        lp.Title AS linked_title,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS link_rank
    FROM PostLinks pl
    JOIN post_engagement pe ON pe.post_id = pl.PostId
    JOIN Posts lp ON lp.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 1
)
SELECT 
    ua.user_id,
    ua.DisplayName AS user_name,
    ua.Reputation,
    ua.post_count,
    ua.total_score,
    ua.avg_score,
    ua.comment_count,
    ua.last_edit,
    ua.score_rank,
    COALESCE(bs1.badge_count, 0) AS gold_badges,
    COALESCE(bs2.badge_count, 0) AS silver_badges,
    bs1.badge_names AS gold_badges_list,
    bs2.badge_names AS silver_badges_list,
    COUNT(pe.post_id) AS recent_posts,
    AVG(pe.Score) AS recent_avg_score,
    SUM(CASE WHEN pe.post_status = 'Closed' THEN 1 ELSE 0 END) AS closed_posts,
    MAX(CASE WHEN lp.link_rank = 1 THEN lp.linked_title END) AS top_linked_post,
    CASE 
        WHEN ua.total_score > 10000 THEN 'Elite'
        WHEN ua.total_score > 1000 THEN 'Active'
        WHEN ua.total_score > 100 THEN 'Rising'
        ELSE 'Newcomer'
    END AS user_tier,
    (ua.total_score - COALESCE(LAG(ua.total_score) OVER (ORDER BY ua.user_creation), 0)) AS score_growth,
    ('Score: ' || CAST(ua.total_score AS VARCHAR) || 
     ' | Posts: ' || CAST(ua.post_count AS VARCHAR) ||
     CASE WHEN COUNT(pe.post_id) > 0 THEN ' | Active' ELSE ' | Inactive' END
    ) AS user_summary
FROM user_activity ua
LEFT JOIN post_engagement pe ON pe.OwnerUserId = ua.user_id
LEFT JOIN linked_posts lp ON lp.PostId = pe.post_id AND lp.link_rank <= 3
LEFT JOIN badge_summary bs1 ON bs1.UserId = ua.user_id AND bs1.Class = 1
LEFT JOIN badge_summary bs2 ON bs2.UserId = ua.user_id AND bs2.Class = 2
WHERE ua.score_rank <= 100
  -- keep users even if they have no recent posts
  AND (pe.post_id IS NULL OR pe.post_id IS NOT NULL)
  AND (ua.last_edit IS NULL OR ua.last_edit >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY))
GROUP BY 
    ua.user_id, ua.DisplayName, ua.Reputation, ua.post_count, ua.total_score, 
    ua.avg_score, ua.comment_count, ua.last_edit, ua.score_rank,
    bs1.badge_count, bs2.badge_count, bs1.badge_names, bs2.badge_names,
    ua.user_creation
HAVING AVG(pe.Score) > 5 OR AVG(pe.Score) IS NULL
ORDER BY ua.total_score DESC, ua.score_rank ASC
FETCH FIRST 50 ROWS ONLY;