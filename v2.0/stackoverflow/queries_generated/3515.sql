-- {"query": "3515.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1545} 

/*  Performance‑benchmarking query – mixes CTEs, window functions, outer joins,
    correlated subqueries, set operators, string handling and NULL logic          */
WITH
/* 1. Compute per‑user badge aggregates (including tag‑based vs named) */
user_badges AS (
    SELECT
        b.UserId,
        COUNT(*)                                     AS total_badges,
        COUNT(*) FILTER (WHERE b.Class = 1)          AS gold,
        COUNT(*) FILTER (WHERE b.Class = 2)          AS silver,
        COUNT(*) FILTER (WHERE b.Class = 3)          AS bronze,
        COUNT(*) FILTER (WHERE b.TagBased = 1)       AS tag_based,
        COUNT(*) FILTER (WHERE b.TagBased = 0)       AS named
    FROM Badges b
    GROUP BY b.UserId
),

/* 2. Compute per‑user post statistics (questions & answers) */
user_posts AS (
    SELECT
        p.OwnerUserId                                 AS user_id,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)      AS ques_cnt,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)      AS ans_cnt,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1)  AS avg_ques_score,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)  AS avg_ans_score,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS total_views,
        MAX(p.CreationDate)                           AS last_post_date
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* 3. Recent activity per user (last 30 days) using window functions */
recent_activity AS (
    SELECT
        u.Id                                           AS user_id,
        COUNT(DISTINCT v.Id)                           AS votes_cast_30d,
        COUNT(DISTINCT c.Id)                           AS comments_30d,
        COUNT(DISTINCT ph.Id)                          AS edits_30d,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(a.activity_date) DESC) AS rn
    FROM Users u
    LEFT JOIN Votes v   ON v.UserId = u.Id
                        AND v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    LEFT JOIN Comments c ON c.UserId = u.Id
                        AND c.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
                        AND ph.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    /* derived activity timestamp (max of the three sources) */
    LEFT JOIN LATERAL (
        SELECT GREATEST(
            COALESCE(v.CreationDate, '1970-01-01'::timestamp),
            COALESCE(c.CreationDate, '1970-01-01'::timestamp),
            COALESCE(ph.CreationDate, '1970-01-01'::timestamp)
        ) AS activity_date
    ) a ON TRUE
    GROUP BY u.Id
),

/* 4. Users who have posted questions containing a specific pattern in title */
pattern_users AS (
    SELECT DISTINCT
        p.OwnerUserId               AS user_id,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS pattern_q_cnt
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- questions only
      AND p.Title ILIKE '%[SQL]%'              -- pattern in title
      AND p.CreationDate >= '2020-01-01'::date
),

/* 5. Assemble the final set – include a UNION ALL to add a dummy “system” row */
final_set AS (
    SELECT
        u.Id                                           AS user_id,
        COALESCE(u.DisplayName, 'Anonymous')           AS display_name,
        u.Reputation,
        ub.total_badges,
        ub.gold,
        ub.silver,
        ub.bronze,
        ub.tag_based,
        ub.named,
        up.ques_cnt,
        up.ans_cnt,
        up.avg_ques_score,
        up.avg_ans_score,
        up.total_views,
        up.last_post_date,
        ra.votes_cast_30d,
        ra.comments_30d,
        ra.edits_30d,
        pu.pattern_q_cnt,
        /* Complex expression: reputation tier with NULL handling */
        CASE
            WHEN u.Reputation IS NULL THEN 'unknown'
            WHEN u.Reputation >= 20000 THEN 'elite'
            WHEN u.Reputation >= 10000 THEN 'high'
            WHEN u.Reputation >= 5000  THEN 'mid'
            ELSE 'low'
        END                                            AS reputation_tier,
        /* Flag indicating if user has both gold badge and >1000 views */
        CASE
            WHEN ub.gold > 0 AND COALESCE(up.total_views,0) > 1000 THEN 1
            ELSE 0
        END                                            AS elite_contributor_flag
    FROM Users u
    LEFT JOIN user_badges ub      ON ub.UserId = u.Id
    LEFT JOIN user_posts up       ON up.user_id = u.Id
    LEFT JOIN recent_activity ra  ON ra.user_id = u.Id
    LEFT JOIN pattern_users pu    ON pu.user_id = u.Id
    WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year'   -- exclude newcomers
      AND (u.Location IS NULL OR u.Location <> 'Antarctica') -- filter out improbable location
    UNION ALL
    SELECT
        0                                             AS user_id,
        'System'                                      AS display_name,
        NULL                                          AS Reputation,
        0                                             AS total_badges,
        0                                             AS gold,
        0                                             AS silver,
        0                                             AS bronze,
        0                                             AS tag_based,
        0                                             AS named,
        0                                             AS ques_cnt,
        0                                             AS ans_cnt,
        NULL                                          AS avg_ques_score,
        NULL                                          AS avg_ans_score,
        0                                             AS total_views,
        NULL                                          AS last_post_date,
        0                                             AS votes_cast_30d,
        0                                             AS comments_30d,
        0                                             AS edits_30d,
        0                                             AS pattern_q_cnt,
        'system'                                      AS reputation_tier,
        0                                             AS elite_contributor_flag
)
SELECT *
FROM final_set
ORDER BY
    elite_contributor_flag DESC,
    gold DESC,
    silver DESC,
    bronze DESC,
    Reputation DESC NULLS LAST,
    user_id;
