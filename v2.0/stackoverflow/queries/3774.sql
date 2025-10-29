-- {"query": "3774.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2943}
WITH
    user_stats AS (
        SELECT
            u.id                                AS user_id,
            u.displayname                       AS display_name,
            u.reputation,
            COALESCE(q.cnt, 0)                  AS question_cnt,
            COALESCE(a.cnt, 0)                  AS answer_cnt,
            COALESCE(b.gold, 0)                 AS gold_badge_cnt,
            COALESCE(b.silver, 0)               AS silver_badge_cnt,
            COALESCE(b.bronze, 0)               AS bronze_badge_cnt,
            COALESCE(v.up_votes, 0)             AS up_vote_cnt,
            COALESCE(v.down_votes, 0)           AS down_vote_cnt,
            COALESCE(v.fav_cnt, 0)              AS favorite_cnt
        FROM users u
        LEFT JOIN (
            SELECT owneruserid, COUNT(*) AS cnt
            FROM posts
            WHERE posttypeid = 1
            GROUP BY owneruserid
        ) q   ON u.id = q.owneruserid
        LEFT JOIN (
            SELECT owneruserid, COUNT(*) AS cnt
            FROM posts
            WHERE posttypeid = 2
            GROUP BY owneruserid
        ) a   ON u.id = a.owneruserid
        LEFT JOIN (
            SELECT
                userid,
                SUM(CASE WHEN class = 1 THEN 1 ELSE 0 END) AS gold,
                SUM(CASE WHEN class = 2 THEN 1 ELSE 0 END) AS silver,
                SUM(CASE WHEN class = 3 THEN 1 ELSE 0 END) AS bronze
            FROM badges
            GROUP BY userid
        ) b   ON u.id = b.userid
        LEFT JOIN (
            SELECT
                p.owneruserid                                    AS userid,
                SUM(CASE WHEN vt.id = 2 THEN 1 ELSE 0 END)      AS up_votes,
                SUM(CASE WHEN vt.id = 3 THEN 1 ELSE 0 END)      AS down_votes,
                SUM(CASE WHEN vt.id = 5 THEN 1 ELSE 0 END)      AS fav_cnt
            FROM votes v
            JOIN posts p          ON v.postid = p.id
            JOIN votetypes vt     ON v.votetypeid = vt.id
            GROUP BY p.owneruserid
        ) v   ON u.id = v.userid
    ),

    tag_extraction AS (
        -- normalize tags like "<tag1><tag2>" into rows
        SELECT
            p.owneruserid                              AS user_id,
            TRIM(BOTH '<>' FROM elem)                  AS tag_name
        FROM posts p,
        LATERAL (
            SELECT
                -- replace leading and trailing angle brackets removal and split on "><"
                unnest(string_to_array(
                    SUBSTRING(p.tags FROM 2 FOR CHAR_LENGTH(p.tags) - 2),
                    '><'
                )) AS elem
        ) AS t
        WHERE p.posttypeid = 1
          AND p.tags IS NOT NULL
    ),

    user_tag_counts AS (
        SELECT
            te.user_id,
            te.tag_name,
            COUNT(*)                                      AS tag_q_cnt,
            ROW_NUMBER() OVER (PARTITION BY te.user_id ORDER BY COUNT(*) DESC) AS rn
        FROM tag_extraction te
        GROUP BY te.user_id, te.tag_name
    ),

    top_tags AS (
        SELECT
            user_id,
            -- STRING_AGG is common; use array_agg + array_to_string if STRING_AGG not available
            STRING_AGG(tag_name, ', ') FILTER (WHERE rn <= 3) AS top_3_tags
        FROM user_tag_counts
        GROUP BY user_id
    ),

    combined AS (
        SELECT
            us.user_id,
            us.display_name,
            us.reputation,
            us.question_cnt,
            us.answer_cnt,
            us.gold_badge_cnt,
            us.silver_badge_cnt,
            us.bronze_badge_cnt,
            us.up_vote_cnt,
            us.down_vote_cnt,
            us.favorite_cnt,
            COALESCE(tt.top_3_tags, '')                AS top_tags,
            RANK() OVER (ORDER BY us.reputation DESC) AS reputation_rank,
            CASE
                WHEN us.answer_cnt = 0 THEN NULL
                ELSE CAST(us.question_cnt AS DECIMAL) / CAST(us.answer_cnt AS DECIMAL)
            END                                         AS q_to_a_ratio,
            CASE
                WHEN (us.up_vote_cnt + us.down_vote_cnt) = 0 THEN 0
                ELSE CAST(us.up_vote_cnt - us.down_vote_cnt AS DECIMAL)
                     / CAST((us.up_vote_cnt + us.down_vote_cnt) AS DECIMAL)
            END                                         AS net_vote_ratio
        FROM user_stats us
        LEFT JOIN top_tags tt ON us.user_id = tt.user_id
    )

SELECT *
FROM combined
WHERE reputation_rank <= 100
   OR (gold_badge_cnt > 5 AND silver_badge_cnt > 10)

UNION ALL

SELECT
    NULL               AS user_id,
    'Aggregated Totals' AS display_name,
    NULL               AS reputation,
    SUM(question_cnt) AS question_cnt,
    SUM(answer_cnt)   AS answer_cnt,
    SUM(gold_badge_cnt)   AS gold_badge_cnt,
    SUM(silver_badge_cnt) AS silver_badge_cnt,
    SUM(bronze_badge_cnt) AS bronze_badge_cnt,
    SUM(up_vote_cnt)   AS up_vote_cnt,
    SUM(down_vote_cnt) AS down_vote_cnt,
    SUM(favorite_cnt)  AS favorite_cnt,
    NULL               AS top_tags,
    NULL               AS reputation_rank,
    NULL               AS q_to_a_ratio,
    NULL               AS net_vote_ratio
FROM combined
WHERE reputation_rank IS NOT NULL

INTERSECT

SELECT *
FROM combined
WHERE q_to_a_ratio IS NOT NULL

ORDER BY reputation_rank ASC NULLS LAST;