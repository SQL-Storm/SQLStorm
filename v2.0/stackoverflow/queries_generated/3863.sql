-- {"query": "3863.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2336} 

WITH 
-- 1. Basic per‑user statistics
user_stats AS (
    SELECT 
        u.Id                                   AS user_id,
        COALESCE(u.DisplayName, 'Anonymous')   AS display_name,
        u.Reputation,
        COUNT(p.Id)                            AS total_posts,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
        SUM(COALESCE(p.Score,0))               AS total_score,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes_given,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes_given,
        MAX(p.CreationDate)                   AS first_post_date,
        MAX(p.LastActivityDate)                AS last_activity_date,
        /* correlated sub‑query: count of positively scored posts */
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id AND p2.Score > 0) AS positive_posts
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- 2. Badge aggregation per user
badge_stats AS (
    SELECT 
        b.UserId                                   AS user_id,
        COUNT(*)                                   AS badge_cnt,
        SUM(CASE b.Class 
                WHEN 1 THEN 5   -- Gold
                WHEN 2 THEN 3   -- Silver
                ELSE 1          -- Bronze
            END)                                   AS badge_score
    FROM Badges b
    GROUP BY b.UserId
),

-- 3. Recent activity flag (last 30 days)
recent_activity AS (
    SELECT 
        p.OwnerUserId                               AS user_id,
        MAX(p.LastActivityDate)                     AS recent_activity
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY p.OwnerUserId
),

-- 4. Top tags used in questions (for set‑operator part)
top_tags AS (
    SELECT 
        t.TagName,
        COUNT(*) AS usage_cnt
    FROM Tags t
    JOIN LATERAL (
        SELECT unnest(string_to_array(
                substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) AS pt ON pt.tag = t.TagName
    GROUP BY t.TagName
    HAVING COUNT(*) > 1000
    ORDER BY usage_cnt DESC
    LIMIT 10
),

-- 5. Combine user stats, badge info and recent activity,
--    compute weighted score and rank within reputation buckets
combined AS (
    SELECT 
        us.user_id,
        us.display_name,
        us.Reputation,
        us.total_posts,
        us.questions,
        us.answers,
        us.total_score,
        us.positive_posts,
        COALESCE(bs.badge_cnt,0)               AS badge_cnt,
        COALESCE(bs.badge_score,0)             AS badge_score,
        ra.recent_activity,
        /* weighted score mixes post score and badge value */
        us.total_score * (1 + COALESCE(bs.badge_score,0)/10.0) 
            + us.positive_posts * 2            AS weighted_score,
        /* reputation bucket for window function */
        CASE 
            WHEN us.Reputation >= 20000 THEN 'high'
            WHEN us.Reputation >= 5000  THEN 'mid'
            ELSE                               'low'
        END                                    AS rep_bucket,
        ROW_NUMBER() OVER (
            PARTITION BY 
                CASE 
                    WHEN us.Reputation >= 20000 THEN 'high'
                    WHEN us.Reputation >= 5000  THEN 'mid'
                    ELSE                               'low'
                END
            ORDER BY us.total_score DESC
        )                                      AS rank_in_bucket,
        /* activity flag with NULL logic */
        CASE 
            WHEN ra.recent_activity IS NULL THEN 'inactive'
            ELSE 'active'
        END                                    AS activity_status
    FROM user_stats us
    LEFT JOIN badge_stats bs      ON bs.user_id = us.user_id
    LEFT JOIN recent_activity ra  ON ra.user_id = us.user_id
)

SELECT 
    c.user_id,
    c.display_name,
    c.Reputation,
    c.total_posts,
    c.questions,
    c.answers,
    c.total_score,
    c.positive_posts,
    c.badge_cnt,
    c.badge_score,
    c.recent_activity,
    ROUND(c.weighted_score,2)          AS weighted_score,
    c.rank_in_bucket,
    c.activity_status
FROM combined c
WHERE c.rank_in_bucket <= 10
  AND (c.weighted_score > 1000 OR c.badge_cnt >= 5)

UNION ALL

/* separator row */
SELECT 
    NULL, '---', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM (SELECT 1) s

UNION ALL

/* list of top tags for reference */
SELECT 
    NULL,
    tt.TagName,
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL,
    NULL, NULL,
    NULL,
    NULL
FROM top_tags tt
ORDER BY 2;
