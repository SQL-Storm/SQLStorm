WITH
badge_agg AS (
    SELECT
        b.UserId,
        COUNT(*)                                   AS total_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        MAX(b.Date)                                AS latest_badge_date
    FROM Badges b
    GROUP BY b.UserId
),
recent_activity AS (
    SELECT
        u.Id                                   AS user_id,
        COUNT(DISTINCT p.Id)                   AS recent_posts,
        COUNT(DISTINCT c.Id)                   AS recent_comments,
        COUNT(DISTINCT v.Id)                   AS recent_votes,
        MAX(p.CreationDate)                    AS last_post_date,
        MAX(c.CreationDate)                    AS last_comment_date,
        MAX(v.CreationDate)                    AS last_vote_date
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id   AND p.CreationDate >= (DATE '2024-10-01' - INTERVAL '90' DAY)
    LEFT JOIN Comments c ON c.UserId = u.Id      AND c.CreationDate >= (DATE '2024-10-01' - INTERVAL '90' DAY)
    LEFT JOIN Votes v    ON v.UserId = u.Id      AND v.CreationDate >= (DATE '2024-10-01' - INTERVAL '90' DAY)
    GROUP BY u.Id
),
user_tag_usage AS (
    SELECT
        p.OwnerUserId                                    AS user_id,
        t.tag,
        COUNT(*)                                         AS tag_appearances,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS tag_rank
    FROM Posts p,
         LATERAL (
           SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')), '><')) AS tag
         ) AS t
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.tag
),
qualified_users AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ba.gold_badges, 0)   AS gold_badges,
        COALESCE(ba.silver_badges, 0) AS silver_badges,
        COALESCE(ra.recent_posts, 0)  AS recent_posts,
        COALESCE(ra.recent_comments,0) AS recent_comments,
        COALESCE(ra.recent_votes,0)    AS recent_votes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS reputation_rank
    FROM Users u
    LEFT JOIN badge_agg ba      ON ba.UserId = u.Id
    LEFT JOIN recent_activity ra ON ra.user_id = u.Id
    WHERE (COALESCE(ba.gold_badges,0) + COALESCE(ba.silver_badges,0)) > 0
      AND (COALESCE(ra.recent_posts,0) + COALESCE(ra.recent_comments,0) + COALESCE(ra.recent_votes,0)) > 0
),
active_unbadged AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ra.recent_posts,0) AS recent_posts,
        COALESCE(ra.recent_comments,0) AS recent_comments,
        ROW_NUMBER() OVER (ORDER BY (COALESCE(ra.recent_posts,0) + COALESCE(ra.recent_comments,0)) DESC) AS activity_rank
    FROM Users u
    LEFT JOIN badge_agg ba      ON ba.UserId = u.Id
    LEFT JOIN recent_activity ra ON ra.user_id = u.Id
    WHERE ba.UserId IS NULL
      AND (COALESCE(ra.recent_posts,0) + COALESCE(ra.recent_comments,0)) >= 10
),
top_posts AS (
    SELECT
        p.OwnerUserId                        AS user_id,
        p.Id                                 AS post_id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS post_rank,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community'
            ELSE 'Open'
        END AS status_flag,
        COALESCE(NULLIF(p.Title, ''), '<no title>') || ' [' || COALESCE(NULLIF(p.Tags, ''), '<no tags>') || ']' AS title_tag_concat,
        (SELECT COUNT(DISTINCT v.UserId)
         FROM Votes v
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS distinct_upvoters
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND (p.Score IS NULL OR p.Score >= 0)
)
SELECT
    qu.Id                                   AS user_id,
    qu.DisplayName,
    qu.Reputation,
    qu.gold_badges,
    qu.silver_badges,
    qu.recent_posts,
    qu.recent_comments,
    qu.recent_votes,
    tp.post_id,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.status_flag,
    tp.title_tag_concat,
    tp.distinct_upvoters,
    CASE
        WHEN tp.post_rank = 1 THEN 'TopPost'
        ELSE 'OtherPost'
    END AS post_category,
    CASE
        WHEN tp.Score > 100 THEN 'HighScore'
        WHEN tp.Score BETWEEN 50 AND 100 THEN 'MidScore'
        ELSE 'LowScore'
    END AS score_bucket,
    qu.reputation_rank,
    tp.post_rank
FROM qualified_users qu
LEFT JOIN top_posts tp
      ON tp.user_id = qu.Id AND tp.post_rank <= 3
WHERE qu.reputation_rank <= 50

UNION ALL

SELECT
    au.Id                                   AS user_id,
    au.DisplayName,
    au.Reputation,
    0                                      AS gold_badges,
    0                                      AS silver_badges,
    NULL                                   AS recent_posts,
    NULL                                   AS recent_comments,
    NULL                                   AS recent_votes,
    tp.post_id,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.status_flag,
    tp.title_tag_concat,
    tp.distinct_upvoters,
    CASE
        WHEN tp.post_rank = 1 THEN 'TopPost_Unbadged'
        ELSE 'OtherPost_Unbadged'
    END AS post_category,
    CASE
        WHEN tp.Score > 100 THEN 'HighScore'
        WHEN tp.Score BETWEEN 50 AND 100 THEN 'MidScore'
        ELSE 'LowScore'
    END AS score_bucket,
    au.activity_rank AS reputation_rank,
    tp.post_rank
FROM active_unbadged au
LEFT JOIN top_posts tp
      ON tp.user_id = au.Id AND tp.post_rank <= 2
WHERE au.activity_rank <= 30
ORDER BY reputation_rank NULLS LAST, post_rank ASC;