WITH
ranked_users AS (
    SELECT
        u.Id                                   AS user_id,
        u.DisplayName                          AS display_name,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
    FROM Users u
),
user_posts AS (
    SELECT
        p.OwnerUserId                                        AS user_id,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)             AS question_cnt,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)             AS answer_cnt,
        COALESCE(SUM(p.Score),0)                             AS total_score,
        COALESCE(AVG(p.Score),0)                             AS avg_score,
        MAX(p.CreationDate)                                  AS last_post_date
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
user_badges AS (
    SELECT
        b.UserId                                            AS user_id,
        COUNT(*) FILTER (WHERE b.Class = 1)                 AS gold_cnt,
        COUNT(*) FILTER (WHERE b.Class = 2)                 AS silver_cnt,
        COUNT(*) FILTER (WHERE b.Class = 3)                 AS bronze_cnt
    FROM Badges b
    GROUP BY b.UserId
),
user_votes AS (
    SELECT
        p.OwnerUserId                                            AS user_id,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)              AS upvote_cnt,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)              AS downvote_cnt
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
latest_post AS (
    SELECT
        u.Id                                                     AS user_id,
        (SELECT p.Title
         FROM Posts p
         WHERE p.OwnerUserId = u.Id
           AND p.Title IS NOT NULL
         ORDER BY p.CreationDate DESC
         LIMIT 1)                                                AS latest_title
    FROM Users u
),
user_tags AS (
    SELECT
        p.OwnerUserId                                            AS user_id,
        LOWER(TRIM(t))                                           AS tag,
        COUNT(*)                                                 AS tag_uses
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(
            string_to_array(
                regexp_replace(p.Tags, '^<|>$', '', 'g'), '><'
            )
        ) AS t
    ) AS taglist
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, LOWER(TRIM(t))
),
tag_popularity AS (
    SELECT
        LOWER(TagName) AS tag,
        Count         AS tag_total_posts
    FROM Tags
    WHERE TagName IS NOT NULL
),
user_tag_score AS (
    SELECT
        ut.user_id,
        SUM(ut.tag_uses * COALESCE(tp.tag_total_posts,0)) AS weighted_tag_score
    FROM user_tags ut
    LEFT JOIN tag_popularity tp ON tp.tag = ut.tag
    GROUP BY ut.user_id
),
post_type_union AS (
    SELECT
        p.OwnerUserId                     AS user_id,
        'question'                        AS post_category,
        COUNT(*)                          AS cnt,
        COALESCE(SUM(p.Score),0)          AS total_score
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId

    UNION ALL

    SELECT
        p.OwnerUserId                     AS user_id,
        'answer'                          AS post_category,
        COUNT(*)                          AS cnt,
        COALESCE(SUM(p.Score),0)          AS total_score
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
post_type_pivot AS (
    SELECT
        user_id,
        MAX(CASE WHEN post_category = 'question' THEN cnt END)         AS total_questions,
        MAX(CASE WHEN post_category = 'answer'   THEN cnt END)         AS total_answers,
        MAX(CASE WHEN post_category = 'question' THEN total_score END) AS question_score_sum,
        MAX(CASE WHEN post_category = 'answer'   THEN total_score END) AS answer_score_sum
    FROM post_type_union
    GROUP BY user_id
)
SELECT
    ru.user_id,
    ru.display_name,
    ru.Reputation,
    ru.rep_rank,
    COALESCE(up.question_cnt,0)                AS questions_posted,
    COALESCE(up.answer_cnt,0)                  AS answers_posted,
    COALESCE(up.total_score,0)                 AS total_post_score,
    ROUND(COALESCE(up.avg_score,0),2)          AS avg_post_score,
    COALESCE(ub.gold_cnt,0)                    AS gold_badges,
    COALESCE(ub.silver_cnt,0)                  AS silver_badges,
    COALESCE(ub.bronze_cnt,0)                  AS bronze_badges,
    COALESCE(uv.upvote_cnt,0)                  AS total_upvotes_received,
    COALESCE(uv.downvote_cnt,0)                AS total_downvotes_received,
    lp.latest_title,
    COALESCE(utag.weighted_tag_score,0)        AS weighted_tag_score,
    COALESCE(ptp.total_questions,0)            AS pivot_questions,
    COALESCE(ptp.total_answers,0)              AS pivot_answers,
    ru.Reputation * (1 + LN(1 + COALESCE(uv.upvote_cnt,0)))      AS reputation_factor,
    CASE WHEN EXISTS (
            SELECT 1 FROM Posts p
            WHERE p.OwnerUserId = ru.user_id
              AND p.LastEditDate IS NOT NULL
        ) THEN 0 ELSE 1 END                     AS never_edited_flag,
    CASE WHEN lp.latest_title IS NOT NULL
          AND up.last_post_date < (CAST('2024-10-01' AS date) - INTERVAL '2 years')
         THEN NULL ELSE lp.latest_title END    AS recent_title_or_null
FROM ranked_users ru
LEFT JOIN user_posts up          ON up.user_id = ru.user_id
LEFT JOIN user_badges ub        ON ub.user_id = ru.user_id
LEFT JOIN user_votes uv         ON uv.user_id = ru.user_id
LEFT JOIN latest_post lp        ON lp.user_id = ru.user_id
LEFT JOIN user_tag_score utag   ON utag.user_id = ru.user_id
LEFT JOIN post_type_pivot ptp   ON ptp.user_id = ru.user_id
WHERE COALESCE(up.question_cnt,0) + COALESCE(up.answer_cnt,0) > 0
ORDER BY ru.rep_rank
LIMIT 100;