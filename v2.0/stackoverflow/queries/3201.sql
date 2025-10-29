-- {"query": "3201.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2981}
WITH
    user_posts AS (
        SELECT
            u.id                         AS user_id,
            COUNT(p.id) FILTER (WHERE p.PostTypeId = 1)               AS question_cnt,
            COUNT(p.id) FILTER (WHERE p.PostTypeId = 2)               AS answer_cnt,
            SUM(p.Score)                                             AS total_score,
            AVG(p.Score)                                             AS avg_score,
            MAX(p.Score)                                             AS max_score,
            COALESCE(SUM(p.ViewCount),0)                             AS total_views,
            MAX(p.CreationDate)                                      AS last_post_dt,
            COUNT(DISTINCT tag)                                      AS distinct_tag_cnt
        FROM Users u
        LEFT JOIN Posts p
            ON p.OwnerUserId = u.id
        LEFT JOIN LATERAL (
            SELECT unnest(string_to_array(
                regexp_replace(p.Tags, '^<|>$', '', 'g'), '><')) AS tag
        ) tags ON TRUE
        GROUP BY u.id
    ),
    user_votes AS (
        SELECT
            v.UserId                                          AS user_id,
            COUNT(*) FILTER (WHERE vt.Id = 2)                 AS upvote_cnt,
            COUNT(*) FILTER (WHERE vt.Id = 3)                 AS downvote_cnt,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE -1 END)       AS net_vote_score,
            MAX(v.CreationDate)                               AS last_vote_dt
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ),
    user_badges AS (
        SELECT
            b.UserId                                          AS user_id,
            COUNT(*)                                          AS badge_cnt,
            COUNT(*) FILTER (WHERE b.Class = 1)               AS gold_cnt,
            COUNT(*) FILTER (WHERE b.Class = 2)               AS silver_cnt,
            COUNT(*) FILTER (WHERE b.Class = 3)               AS bronze_cnt,
            MAX(b.Date)                                       AS last_badge_dt
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_activity AS (
        SELECT
            u.id                                              AS user_id,
            GREATEST(
                COALESCE(p.last_post_dt,      TIMESTAMP '1970-01-01'),
                COALESCE(v.last_vote_dt,     TIMESTAMP '1970-01-01'),
                COALESCE(c.last_comment_dt,  TIMESTAMP '1970-01-01')
            )                                                  AS last_activity_dt
        FROM Users u
        LEFT JOIN (
            SELECT OwnerUserId, MAX(CreationDate) AS last_post_dt
            FROM Posts
            GROUP BY OwnerUserId
        ) p ON p.OwnerUserId = u.id
        LEFT JOIN (
            SELECT UserId, MAX(CreationDate) AS last_vote_dt
            FROM Votes
            GROUP BY UserId
        ) v ON v.UserId = u.id
        LEFT JOIN (
            SELECT UserId, MAX(CreationDate) AS last_comment_dt
            FROM Comments
            GROUP BY UserId
        ) c ON c.UserId = u.id
    ),
    ranked_users AS (
        SELECT
            ra.user_id,
            ra.last_activity_dt,
            ROW_NUMBER() OVER (ORDER BY ra.last_activity_dt DESC) AS activity_rank
        FROM recent_activity ra
        WHERE ra.last_activity_dt > (CAST('2024-10-01' AS DATE) - INTERVAL '180 days')
    ),
    main_block AS (
        SELECT
            u.id                                    AS user_id,
            u.DisplayName                           AS display_name,
            u.Reputation                            AS reputation,
            COALESCE(up.question_cnt,0)             AS questions,
            COALESCE(up.answer_cnt,0)               AS answers,
            COALESCE(up.total_score,0)              AS total_post_score,
            COALESCE(up.avg_score,0)                AS avg_post_score,
            COALESCE(up.max_score,0)                AS max_post_score,
            COALESCE(up.total_views,0)              AS total_views,
            COALESCE(up.distinct_tag_cnt,0)         AS distinct_tags,
            COALESCE(uv.upvote_cnt,0)               AS upvotes_given,
            COALESCE(uv.downvote_cnt,0)             AS downvotes_given,
            COALESCE(uv.net_vote_score,0)           AS net_vote_score,
            COALESCE(ub.badge_cnt,0)                AS badge_count,
            COALESCE(ub.gold_cnt,0)                 AS gold_badges,
            COALESCE(ub.silver_cnt,0)               AS silver_badges,
            COALESCE(ub.bronze_cnt,0)               AS bronze_badges,
            ra.last_activity_dt                     AS last_activity,
            ru.activity_rank                        AS activity_rank,
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM Posts p
                    WHERE p.OwnerUserId = u.id
                      AND p.PostTypeId = 1
                      AND p.Tags LIKE '%<sql>%'
                ) THEN 1 ELSE 0
            END                                      AS has_sql_tag_question
        FROM Users u
        LEFT JOIN user_posts   up ON up.user_id   = u.id
        LEFT JOIN user_votes   uv ON uv.user_id   = u.id
        LEFT JOIN user_badges  ub ON ub.user_id   = u.id
        LEFT JOIN recent_activity ra ON ra.user_id = u.id
        LEFT JOIN ranked_users ru     ON ru.user_id = u.id
        WHERE u.Reputation >= 1000
    ),
    secondary_block AS (
        SELECT
            u.id                                    AS user_id,
            u.DisplayName                           AS display_name,
            u.Reputation                            AS reputation,
            0                                       AS questions,
            0                                       AS answers,
            0                                       AS total_post_score,
            0                                       AS avg_post_score,
            0                                       AS max_post_score,
            0                                       AS total_views,
            0                                       AS distinct_tags,
            0                                       AS upvotes_given,
            0                                       AS downvotes_given,
            0                                       AS net_vote_score,
            COALESCE(ub.badge_cnt,0)                AS badge_count,
            COALESCE(ub.gold_cnt,0)                 AS gold_badges,
            COALESCE(ub.silver_cnt,0)               AS silver_badges,
            COALESCE(ub.bronze_cnt,0)               AS bronze_badges,
            NULL                                    AS last_activity,
            NULL                                    AS activity_rank,
            0                                       AS has_sql_tag_question
        FROM Users u
        JOIN user_badges ub ON ub.user_id = u.id
        LEFT JOIN user_posts up ON up.user_id = u.id
        WHERE up.user_id IS NULL
          AND u.Reputation < 1000
    ),
    main_limited AS (
        SELECT *
        FROM main_block
        ORDER BY activity_rank IS NULL, activity_rank, reputation DESC
        LIMIT 100
    ),
    secondary_limited AS (
        SELECT *
        FROM secondary_block
        ORDER BY reputation DESC
        LIMIT 50
    )
SELECT *
FROM main_limited
UNION ALL
SELECT *
FROM secondary_limited;