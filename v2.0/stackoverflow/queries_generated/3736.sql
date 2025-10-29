-- {"query": "3736.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3244} 

WITH
    -- Aggregate post statistics per user
    user_posts AS (
        SELECT
            u.id                                   AS user_id,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_count,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_count,
            SUM(p.score)                           AS total_score,
            MAX(p.creationdate)                    AS last_post_date
        FROM users u
        LEFT JOIN posts p ON p.owneruserid = u.id
        GROUP BY u.id
    ),

    -- Aggregate badge counts per user
    user_badges AS (
        SELECT
            b.userid,
            COUNT(*) FILTER (WHERE b.class = 1)   AS gold_badges,
            COUNT(*) FILTER (WHERE b.class = 2)   AS silver_badges,
            COUNT(*) FILTER (WHERE b.class = 3)   AS bronze_badges,
            SUM(CASE WHEN b.tagbased = 1 THEN 1 ELSE 0 END) AS tag_badges
        FROM badges b
        GROUP BY b.userid
    ),

    -- Net vote score and favorite count per user (via posts)
    user_votes AS (
        SELECT
            p.owneruserid                         AS user_id,
            SUM(CASE
                WHEN v.votetypeid = 2 THEN 1       -- upvote
                WHEN v.votetypeid = 3 THEN -1      -- downvote
                ELSE 0
            END)                                   AS net_votes,
            COUNT(*) FILTER (WHERE v.votetypeid = 5) AS favorite_count
        FROM votes v
        JOIN posts p ON p.id = v.postid
        GROUP BY p.owneruserid
    ),

    -- Tags used by each user, concatenated into a comma‑separated list
    user_tags AS (
        SELECT
            p.owneruserid                         AS user_id,
            STRING_AGG(DISTINCT tag, ',')         AS tag_list
        FROM posts p,
             LATERAL regexp_split_to_table(p.tags, '[><]+') AS tag
        WHERE p.tags IS NOT NULL
        GROUP BY p.owneruserid
    ),

    -- Combine all user‑level metrics
    user_metrics AS (
        SELECT
            u.id                                   AS user_id,
            u.displayname,
            u.reputation,
            COALESCE(up.question_count,0)          AS question_count,
            COALESCE(up.answer_count,0)            AS answer_count,
            COALESCE(up.total_score,0)             AS total_score,
            COALESCE(ub.gold_badges,0)             AS gold_badges,
            COALESCE(ub.silver_badges,0)           AS silver_badges,
            COALESCE(ub.bronze_badges,0)           AS bronze_badges,
            COALESCE(ub.tag_badges,0)              AS tag_badges,
            COALESCE(uv.net_votes,0)               AS net_votes,
            COALESCE(uv.favorite_count,0)          AS favorite_count,
            COALESCE(ut.tag_list,'')               AS tag_list,
            GREATEST(
                COALESCE(up.last_post_date, TIMESTAMP '1970-01-01'),
                COALESCE(
                    (SELECT MAX(date) FROM badges b WHERE b.userid = u.id),
                    TIMESTAMP '1970-01-01'
                )
            )                                      AS last_activity,
            (SELECT MIN(p.creationdate)
             FROM posts p
             WHERE p.owneruserid = u.id)          AS first_post_date
        FROM users u
        LEFT JOIN user_posts   up ON up.user_id   = u.id
        LEFT JOIN user_badges  ub ON ub.userid    = u.id
        LEFT JOIN user_votes   uv ON uv.user_id   = u.id
        LEFT JOIN user_tags    ut ON ut.user_id   = u.id
    ),

    -- Compute a composite ranking score
    ranked_users AS (
        SELECT
            um.*,
            CASE
                WHEN um.reputation >= 20000 THEN 'High'
                WHEN um.reputation >= 5000  THEN 'Medium'
                ELSE 'Low'
            END                                   AS reputation_tier,
            (um.reputation * 0.5
             + (um.gold_badges   * 100)
             + (um.silver_badges * 50)
             + (um.bronze_badges * 20)
             + (um.net_votes     * 0.2)
            )                                      AS composite_score,
            ROW_NUMBER() OVER (ORDER BY
                (um.reputation * 0.5
                 + (um.gold_badges   * 100)
                 + (um.silver_badges * 50)
                 + (um.bronze_badges * 20)
                 + (um.net_votes     * 0.2)
                ) DESC)                           AS rank_position,
            u.displayname || ' (' || u.id || ')' AS display_with_id,
            NULLIF(u.websiteurl, '')             AS clean_website,
            (u.websiteurl IS NOT NULL AND u.websiteurl <> '') AS has_website,
            (u.location IS NOT NULL AND u.location <> '')     AS has_location,
            (u.aboutme IS NOT NULL AND u.aboutme <> '')       AS has_aboutme
        FROM user_metrics um
        JOIN users u ON u.id = um.user_id
    ),

    -- Split the top‑1000 ranked users into two segments using UNION ALL
    segmented_users AS (
        SELECT
            user_id,
            displayname,
            reputation,
            rank_position,
            composite_score,
            'Top'    AS segment
        FROM ranked_users
        WHERE rank_position <= 500

        UNION ALL

        SELECT
            user_id,
            displayname,
            reputation,
            rank_position,
            composite_score,
            'Bottom' AS segment
        FROM ranked_users
        WHERE rank_position > 500 AND rank_position <= 1000
    )

SELECT
    su.user_id,
    su.displayname,
    su.reputation,
    su.rank_position,
    su.composite_score,
    su.segment,
    ru.reputation_tier,
    ru.question_count,
    ru.answer_count,
    ru.total_score,
    ru.tag_list,
    ru.first_post_date,
    ru.last_activity
FROM segmented_users su
JOIN ranked_users ru ON ru.user_id = su.user_id
ORDER BY su.rank_position;
