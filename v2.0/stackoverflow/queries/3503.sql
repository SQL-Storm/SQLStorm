-- {"query": "3503.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3427}
WITH
    user_posts AS (
        SELECT
            p.OwnerUserId                         AS user_id,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS question_cnt,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS answer_cnt,
            SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS question_score,
            SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS answer_score,
            MAX(p.CreationDate)                  AS last_post_dt
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    user_badges AS (
        SELECT
            b.UserId                                   AS user_id,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END)    AS gold_cnt,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END)    AS silver_cnt,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END)    AS bronze_cnt,
            COUNT(*)                                   AS total_badges
        FROM Badges b
        GROUP BY b.UserId
    ),
    post_votes AS (
        SELECT
            p.OwnerUserId                         AS user_id,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes_given,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes_given
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE v.VoteTypeId IN (2,3)
        GROUP BY p.OwnerUserId
    ),
    recent_activity AS (
        SELECT
            u.Id                                   AS user_id,
            (SELECT MAX(p.CreationDate)
             FROM Posts p
             WHERE p.OwnerUserId = u.Id)          AS most_recent_post,
            (SELECT MAX(c.CreationDate)
             FROM Comments c
             WHERE c.UserId = u.Id)               AS most_recent_comment
        FROM Users u
    ),
    tag_usage AS (
        SELECT
            p.OwnerUserId                         AS user_id,
            t.tag,
            COUNT(*)                              AS tag_cnt
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
        ) t
        WHERE p.OwnerUserId IS NOT NULL
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, t.tag
    ),
    top_tags AS (
        SELECT
            user_id,
            STRING_AGG(tag, ', ') FILTER (WHERE rn <= 5) AS top_5_tags
        FROM (
            SELECT
                user_id,
                tag,
                tag_cnt,
                ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY tag_cnt DESC) AS rn
            FROM tag_usage
        ) ranked
        GROUP BY user_id
    ),
    combined AS (
        SELECT
            u.Id                                                            AS user_id,
            COALESCE(u.DisplayName, 'Anonymous')                            AS display_name,
            u.Reputation,
            up.question_cnt,
            up.answer_cnt,
            up.question_score,
            up.answer_score,
            ub.gold_cnt,
            ub.silver_cnt,
            ub.bronze_cnt,
            ub.total_badges,
            pv.up_votes_given,
            pv.down_votes_given,
            (pv.up_votes_given - pv.down_votes_given)                       AS net_votes_given,
            ra.most_recent_post,
            ra.most_recent_comment,
            tt.top_5_tags,
            CASE
                WHEN up.answer_cnt = 0 THEN NULL
                ELSE ROUND(CAST(up.answer_score AS DECIMAL) / NULLIF(up.answer_cnt,0), 2)
            END                                                             AS avg_answer_score,
            (COALESCE(up.question_score,0) + COALESCE(up.answer_score,0)) +
            (COALESCE(pv.up_votes_given,0) - COALESCE(pv.down_votes_given,0)) +
            (COALESCE(ub.total_badges,0) * 10)                                         AS composite_score,
            RANK() OVER (ORDER BY (COALESCE(up.question_score,0) + COALESCE(up.answer_score,0)) DESC) AS score_rank
        FROM Users u
        LEFT JOIN user_posts up       ON up.user_id = u.Id
        LEFT JOIN user_badges ub      ON ub.user_id = u.Id
        LEFT JOIN post_votes pv       ON pv.user_id = u.Id
        LEFT JOIN recent_activity ra  ON ra.user_id = u.Id
        LEFT JOIN top_tags tt         ON tt.user_id = u.Id
        WHERE u.Reputation > 1000

        UNION ALL

        SELECT
            u.Id,
            (COALESCE(u.DisplayName, 'Anonymous') || ' (low rep)')          AS display_name,
            u.Reputation,
            up.question_cnt,
            up.answer_cnt,
            up.question_score,
            up.answer_score,
            ub.gold_cnt,
            ub.silver_cnt,
            ub.bronze_cnt,
            ub.total_badges,
            pv.up_votes_given,
            pv.down_votes_given,
            (pv.up_votes_given - pv.down_votes_given)                     AS net_votes_given,
            ra.most_recent_post,
            ra.most_recent_comment,
            tt.top_5_tags,
            CASE
                WHEN up.answer_cnt = 0 THEN NULL
                ELSE ROUND(CAST(up.answer_score AS DECIMAL) / NULLIF(up.answer_cnt,0), 2)
            END                                                            AS avg_answer_score,
            (COALESCE(up.question_score,0) + COALESCE(up.answer_score,0)) +
            (COALESCE(pv.up_votes_given,0) - COALESCE(pv.down_votes_given,0)) +
            (COALESCE(ub.total_badges,0) * 10)                                         AS composite_score,
            CAST(NULL AS INTEGER)                                                            AS score_rank
        FROM Users u
        LEFT JOIN user_posts up       ON up.user_id = u.Id
        LEFT JOIN user_badges ub      ON ub.user_id = u.Id
        LEFT JOIN post_votes pv       ON pv.user_id = u.Id
        LEFT JOIN recent_activity ra  ON ra.user_id = u.Id
        LEFT JOIN top_tags tt         ON tt.user_id = u.Id
        WHERE u.Reputation BETWEEN 1 AND 1000
    )
SELECT c.user_id,
       c.display_name,
       c.Reputation,
       c.question_cnt,
       c.answer_cnt,
       c.question_score,
       c.answer_score,
       c.gold_cnt,
       c.silver_cnt,
       c.bronze_cnt,
       c.total_badges,
       c.up_votes_given,
       c.down_votes_given,
       c.net_votes_given,
       c.most_recent_post,
       c.most_recent_comment,
       c.top_5_tags,
       c.avg_answer_score,
       c.composite_score,
       c.score_rank
FROM combined c
WHERE NOT EXISTS (
        SELECT 1
        FROM Badges b
        WHERE b.UserId = c.user_id
          AND b.Name = 'Moderator'
      )
ORDER BY c.composite_score DESC
LIMIT 10;