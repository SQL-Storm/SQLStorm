-- {"query": "3928.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1639} 

/*  Benchmark query – mixes CTEs, window functions, outer joins, correlated subqueries,
    set operators, string aggregation, and extensive NULL handling                 */

WITH
-- 1️⃣ Per‑user activity summary
user_stats AS (
    SELECT
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id)                  AS total_posts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS total_questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS total_answers,
        SUM(CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END) AS sum_post_score,
        AVG(CASE WHEN p.Score IS NULL THEN NULL ELSE p.Score END) AS avg_post_score,
        COUNT(DISTINCT b.Id)                  AS badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS bronze_badges,
        MAX(p.CreationDate)                  AS last_post_date,
        MAX(COALESCE(v.CreationDate, '1970-01-01')) AS last_vote_date
    FROM Users u
    LEFT JOIN Posts p      ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b     ON b.UserId = u.Id
    LEFT JOIN Votes v      ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- 2️⃣ Tag usage per user (derived from question tags)
tag_usage AS (
    SELECT
        p.OwnerUserId                               AS user_id,
        STRING_AGG(DISTINCT t.TagName, ',')         AS tags_used,
        COUNT(DISTINCT t.Id)                        AS distinct_tag_count,
        SUM(CASE WHEN t.IsModeratorOnly = 1 THEN 1 ELSE 0 END) AS moderator_tags,
        SUM(CASE WHEN t.IsRequired = 1 THEN 1 ELSE 0 END)        AS required_tags
    FROM Posts p
    JOIN LATERAL (
        SELECT trim(both '<>' FROM unnest(string_to_array(p.Tags, '><'))) AS tag_text
    ) AS raw_tag ON TRUE
    JOIN Tags t ON t.TagName = raw_tag.tag_text
    WHERE p.PostTypeId = 1                -- only questions have Tags
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

-- 3️⃣ Recent activity snapshot (last 30 days) using a correlated sub‑query
recent_activity AS (
    SELECT
        u.Id                                   AS user_id,
        COUNT(*)                               AS recent_posts,
        COUNT(*) FILTER (WHERE p.Score >= 10)  AS high_score_posts,
        COUNT(DISTINCT v.Id)                   AS recent_votes,
        MAX(p.CreationDate)                   AS most_recent_post
    FROM Users u
    LEFT JOIN Posts p
        ON p.OwnerUserId = u.Id
       AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    LEFT JOIN Votes v
        ON v.UserId = u.Id
       AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY u.Id
),

-- 4️⃣ Combined user view (union of active and inactive users for set‑operator stress)
combined_users AS (
    SELECT
        us.user_id,
        us.DisplayName,
        us.Reputation,
        us.total_posts,
        us.sum_post_score,
        tu.tags_used,
        ra.recent_posts,
        ROW_NUMBER() OVER (PARTITION BY us.user_id ORDER BY us.Reputation DESC) AS rank_by_rep
    FROM user_stats us
    LEFT JOIN tag_usage tu   ON tu.user_id = us.user_id
    LEFT JOIN recent_activity ra ON ra.user_id = us.user_id
    WHERE us.total_posts > 0

    UNION ALL

    SELECT
        u.Id                           AS user_id,
        u.DisplayName,
        u.Reputation,
        0                              AS total_posts,
        0                              AS sum_post_score,
        NULL                           AS tags_used,
        0                              AS recent_posts,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.Reputation DESC) AS rank_by_rep
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
      AND u.Reputation > 1000
)

SELECT
    cu.user_id,
    cu.DisplayName,
    cu.Reputation,
    cu.total_posts,
    cu.sum_post_score,
    COALESCE(cu.tags_used, '(none)')                     AS tags_used,
    cu.recent_posts,
    cu.rank_by_rep,
    -- Windowed calculation: percentile of reputation among all returned rows
    PERCENT_RANK() OVER (ORDER BY cu.Reputation)        AS reputation_percentile,
    -- Complex expression mixing NULL logic and string manipulation
    CASE
        WHEN cu.tags_used IS NULL THEN 'No tags'
        WHEN CHAR_LENGTH(cu.tags_used) > 30 THEN SUBSTRING(cu.tags_used FROM 1 FOR 27) || '…'
        ELSE cu.tags_used
    END                                                AS tags_display
FROM combined_users cu
FULL OUTER JOIN (
    /* 5️⃣ Auxiliary set to stress a FULL OUTER JOIN – recent close‑reason activity */
    SELECT
        ph.UserId           AS user_id,
        COUNT(*)            AS close_votes,
        MAX(ph.CreationDate) AS last_close_vote
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10                     -- Post Closed
      AND ph.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY ph.UserId
) cr ON cr.user_id = cu.user_id
WHERE cu.reputation_percentile IS NOT NULL
ORDER BY cu.Reputation DESC
LIMIT 100;
