WITH
    user_posts AS (
        SELECT
            u.id                                      AS user_id,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
            SUM(p.score)  FILTER (WHERE p.posttypeid = 1) AS question_score_sum,
            SUM(p.score)  FILTER (WHERE p.posttypeid = 2) AS answer_score_sum,
            MAX(p.creationdate)                         AS last_post_dt
        FROM   users u
        LEFT JOIN posts p ON p.owneruserid = u.id
        GROUP BY u.id
    ),

    user_badges AS (
        SELECT
            b.userid                                 AS user_id,
            COUNT(*) FILTER (WHERE b.class = 1)      AS gold_cnt,
            COUNT(*) FILTER (WHERE b.class = 2)      AS silver_cnt,
            COUNT(*) FILTER (WHERE b.class = 3)      AS bronze_cnt,
            MAX(b.date)                              AS last_badge_dt
        FROM   badges b
        GROUP BY b.userid
    ),

    -- Expand tags per answer owner using a lateral-derived table to avoid set-returning functions inside aggregates
    user_tags AS (
        SELECT
            a.owneruserid                                 AS user_id,
            COUNT(DISTINCT tag)                            AS distinct_tag_cnt
        FROM   posts a
        JOIN   posts p ON p.id = a.parentid
        CROSS JOIN LATERAL (
            SELECT regexp_replace(p.tags, '^<|>$', '', 'g') AS cleaned_tags
        ) t1
        CROSS JOIN LATERAL (
            SELECT UNNEST(string_to_array(t1.cleaned_tags, '><')) AS tag
        ) t2
        WHERE  a.posttypeid = 2
          AND  p.tags IS NOT NULL
        GROUP BY a.owneruserid
    ),

    recent_vote AS (
        SELECT
            v.userid,
            v.postid,
            v.votetypeid,
            v.creationdate,
            ROW_NUMBER() OVER (PARTITION BY v.userid ORDER BY v.creationdate DESC) AS rn
        FROM   votes v
        WHERE  v.userid IS NOT NULL
    ),

    user_metrics AS (
        SELECT
            u.id,
            u.displayname,
            COALESCE(up.question_cnt,   0)      AS question_cnt,
            COALESCE(up.answer_cnt,     0)      AS answer_cnt,
            COALESCE(up.question_score_sum,0)   AS question_score_sum,
            COALESCE(up.answer_score_sum,  0)   AS answer_score_sum,
            COALESCE(ub.gold_cnt,      0)       AS gold_cnt,
            COALESCE(ub.silver_cnt,    0)       AS silver_cnt,
            COALESCE(ub.bronze_cnt,    0)       AS bronze_cnt,
            COALESCE(ut.distinct_tag_cnt,0)     AS distinct_tag_cnt,
            GREATEST(
                COALESCE(up.last_post_dt,   TIMESTAMP '1970-01-01'),
                COALESCE(ub.last_badge_dt,  TIMESTAMP '1970-01-01'),
                COALESCE(rv.creationdate,   TIMESTAMP '1970-01-01')
            )                                    AS last_activity_dt,
            (u.reputation
             + COALESCE(up.question_score_sum,0)
             + COALESCE(up.answer_score_sum,0)
             + 10*COALESCE(ub.gold_cnt,0)
             + 5 *COALESCE(ub.silver_cnt,0)
             + 1 *COALESCE(ub.bronze_cnt,0)
            )                                    AS composite_score
        FROM   users u
        LEFT JOIN user_posts   up ON up.user_id = u.id
        LEFT JOIN user_badges  ub ON ub.user_id = u.id
        LEFT JOIN user_tags    ut ON ut.user_id = u.id
        LEFT JOIN (
            SELECT userid, creationdate
            FROM   recent_vote
            WHERE  rn = 1
        ) rv ON rv.userid = u.id
    ),

    ranked_users AS (
        SELECT
            id,
            displayname,
            question_cnt,
            answer_cnt,
            distinct_tag_cnt,
            gold_cnt,
            silver_cnt,
            bronze_cnt,
            composite_score,
            last_activity_dt,
            RANK()     OVER (ORDER BY composite_score DESC) AS score_rank,
            ROW_NUMBER() OVER (ORDER BY (question_cnt+answer_cnt) DESC) AS activity_rank
        FROM   user_metrics
    )

SELECT
    ru.id,
    ru.displayname,
    ru.question_cnt,
    ru.answer_cnt,
    ru.distinct_tag_cnt,
    ru.gold_cnt,
    ru.silver_cnt,
    ru.bronze_cnt,
    ru.composite_score,
    ru.score_rank,
    ru.activity_rank,
    CASE
        WHEN ru.last_activity_dt > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)  THEN 'Active'
        WHEN ru.last_activity_dt > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY) THEN 'Semi-Active'
        ELSE 'Inactive'
    END AS activity_status
FROM   ranked_users ru
WHERE  ru.composite_score > 0

UNION ALL

SELECT
    NULL                      AS id,
    '--- TOP 10 QUESTIONS BY SCORE ---' AS displayname,
    NULL AS question_cnt,
    NULL AS answer_cnt,
    NULL AS distinct_tag_cnt,
    NULL AS gold_cnt,
    NULL AS silver_cnt,
    NULL AS bronze_cnt,
    NULL AS composite_score,
    NULL AS score_rank,
    NULL AS activity_rank,
    NULL AS activity_status

ORDER BY score_rank
LIMIT 100;