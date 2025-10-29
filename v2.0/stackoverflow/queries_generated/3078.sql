-- {"query": "3078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3419} 

WITH
    -- aggregate basic post stats per user
    user_posts AS (
        SELECT
            u.id                     AS user_id,
            u.displayname,
            u.reputation,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
            SUM(p.score) FILTER (WHERE p.posttypeid = 1) AS question_score_sum,
            SUM(p.score) FILTER (WHERE p.posttypeid = 2) AS answer_score_sum,
            MAX(p.creationdate)                     AS last_post_dt
        FROM users u
        LEFT JOIN posts p ON p.owneruserid = u.id
        GROUP BY u.id, u.displayname, u.reputation
    ),

    -- aggregate badge counts per user
    user_badges AS (
        SELECT
            b.userid               AS user_id,
            COUNT(*)               AS badge_total,
            COUNT(*) FILTER (WHERE b.class = 1) AS gold_cnt,
            COUNT(*) FILTER (WHERE b.class = 2) AS silver_cnt,
            COUNT(*) FILTER (WHERE b.class = 3) AS bronze_cnt,
            MAX(b.date)            AS last_badge_dt
        FROM badges b
        GROUP BY b.userid
    ),

    -- votes given by each user
    user_votes AS (
        SELECT
            v.userid                                   AS user_id,
            SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS up_votes_given,
            SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS down_votes_given,
            SUM(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS fav_given,
            COUNT(*) FILTER (WHERE v.votetypeid = 8)          AS bounties_started,
            COUNT(*) FILTER (WHERE v.votetypeid = 9)          AS bounties_awarded
        FROM votes v
        WHERE v.userid IS NOT NULL
        GROUP BY v.userid
    ),

    -- explode tags per post and per user
    user_tags_exploded AS (
        SELECT
            p.owneruserid AS user_id,
            UNNEST(string_to_array(REPLACE(REPLACE(p.tags, '<', ''), '>', ''), '><')) AS tag
        FROM posts p
        WHERE p.tags IS NOT NULL
    ),

    -- count tag usage per user, rank tags per user
    user_tags AS (
        SELECT
            ue.user_id,
            t.tagname,
            COUNT(*)                                     AS tag_use_cnt,
            ROW_NUMBER() OVER (PARTITION BY ue.user_id ORDER BY COUNT(*) DESC) AS tag_rank
        FROM user_tags_exploded ue
        JOIN tags t ON t.tagname = ue.tag
        GROUP BY ue.user_id, t.tagname
    ),

    -- recent activity flags (30 days window)
    recent_activity AS (
        SELECT
            u.id                     AS user_id,
            EXISTS (
                SELECT 1 FROM posts p
                WHERE p.owneruserid = u.id
                  AND p.posttypeid = 1
                  AND p.creationdate > now() - INTERVAL '30 days'
            )                        AS has_recent_question,
            EXISTS (
                SELECT 1 FROM posts p
                WHERE p.owneruserid = u.id
                  AND p.posttypeid = 2
                  AND p.creationdate > now() - INTERVAL '30 days'
            )                        AS has_recent_answer
        FROM users u
    ),

    -- combine everything, compute a composite activity score and rank
    combined AS (
        SELECT
            COALESCE(up.user_id, ub.user_id, uv.user_id, ut.user_id, ra.user_id) AS user_id,
            COALESCE(up.displayname, (SELECT displayname FROM users WHERE id = COALESCE(ub.user_id, uv.user_id, ut.user_id, ra.user_id))) AS displayname,
            COALESCE(up.reputation, 0)                                   AS reputation,
            COALESCE(up.question_cnt, 0)                                 AS question_cnt,
            COALESCE(up.answer_cnt, 0)                                   AS answer_cnt,
            COALESCE(up.question_score_sum, 0)                           AS question_score_sum,
            COALESCE(up.answer_score_sum, 0)                             AS answer_score_sum,
            COALESCE(ub.badge_total, 0)                                 AS badge_total,
            COALESCE(ub.gold_cnt, 0)                                     AS gold_cnt,
            COALESCE(ub.silver_cnt, 0)                                   AS silver_cnt,
            COALESCE(ub.bronze_cnt, 0)                                   AS bronze_cnt,
            COALESCE(uv.up_votes_given, 0)                               AS up_votes_given,
            COALESCE(uv.down_votes_given, 0)                             AS down_votes_given,
            COALESCE(uv.fav_given, 0)                                    AS fav_given,
            COALESCE(uv.bounties_started, 0)                             AS bounties_started,
            COALESCE(uv.bounties_awarded, 0)                             AS bounties_awarded,
            COALESCE(ut.tagname, '(none)')                               AS top_tag,
            COALESCE(ut.tag_use_cnt, 0)                                  AS top_tag_use_cnt,
            ra.has_recent_question,
            ra.has_recent_answer,
            ROW_NUMBER() OVER (
                ORDER BY
                    (COALESCE(up.reputation,0) * 1.0) +
                    (COALESCE(up.question_score_sum,0) * 2) +
                    (COALESCE(up.answer_score_sum,0) * 3) +
                    (COALESCE(ub.badge_total,0) * 5) DESC
            )                                                            AS activity_rank
        FROM user_posts up
        FULL OUTER JOIN user_badges ub   ON up.user_id = ub.user_id
        FULL OUTER JOIN user_votes  uv   ON COALESCE(up.user_id, ub.user_id) = uv.user_id
        LEFT JOIN (
            SELECT user_id, tagname, tag_use_cnt,
                   ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY tag_use_cnt DESC) AS rn
            FROM user_tags
        ) ut ON COALESCE(up.user_id, ub.user_id) = ut.user_id AND ut.rn = 1
        LEFT JOIN recent_activity ra   ON COALESCE(up.user_id, ub.user_id) = ra.user_id
    ),

    -- users with absolutely no activity (for set‑operator demo)
    inactive_users AS (
        SELECT
            u.id          AS user_id,
            u.displayname,
            u.reputation,
            0             AS question_cnt,
            0             AS answer_cnt,
            0             AS question_score_sum,
            0             AS answer_score_sum,
            0             AS badge_total,
            0             AS gold_cnt,
            0             AS silver_cnt,
            0             AS bronze_cnt,
            0             AS up_votes_given,
            0             AS down_votes_given,
            0             AS fav_given,
            0             AS bounties_started,
            0             AS bounties_awarded,
            '(none)'      AS top_tag,
            0             AS top_tag_use_cnt,
            FALSE         AS has_recent_question,
            FALSE         AS has_recent_answer,
            NULL          AS activity_rank
        FROM users u
        WHERE NOT EXISTS (SELECT 1 FROM posts p WHERE p.owneruserid = u.id)
    )

-- final result set: top active users UNION ALL a sample of inactive users
SELECT *
FROM combined
WHERE activity_rank <= 100

UNION ALL

SELECT *
FROM inactive_users
ORDER BY activity_rank NULLS LAST
LIMIT 50;
