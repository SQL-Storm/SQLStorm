-- {"query": "3389.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3101} 

WITH
    top_users AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(u.Location, 'Unknown')                     AS Location,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC,
                                         u.CreationDate)   AS rep_rank
        FROM Users u
        WHERE u.Reputation > 10000
    ),
    badge_summary AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1)                AS gold,
            COUNT(*) FILTER (WHERE b.Class = 2)                AS silver,
            COUNT(*) FILTER (WHERE b.Class = 3)                AS bronze,
            COUNT(*)                                           AS total_badges,
            STRING_AGG(DISTINCT b.Name, ', ')                  AS badge_names
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_activity AS (
        SELECT
            p.OwnerUserId                                    AS UserId,
            MAX(p.CreationDate)                              AS last_post_date,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)         AS question_cnt,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)         AS answer_cnt,
            SUM(p.Score)                                     AS total_score
        FROM Posts p
        WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
        GROUP BY p.OwnerUserId
    ),
    vote_agg AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END)       AS upvotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END)       AS downvotes,
            SUM(CASE WHEN vt.Id = 5 THEN 1 ELSE 0 END)       AS favorites,
            COUNT(*) FILTER (WHERE vt.Id = 6)                AS close_votes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ),
    tag_explode AS (
        SELECT
            p.Id                                            AS PostId,
            UNNEST(string_to_array(TRIM(BOTH '><' FROM p.Tags), '><')) AS Tag
        FROM Posts p
        WHERE p.Tags IS NOT NULL
    ),
    tag_counts AS (
        SELECT
            te.Tag,
            COUNT(*)                                         AS tag_usage,
            MIN(p.CreationDate)                              AS first_used,
            MAX(p.CreationDate)                              AS last_used
        FROM tag_explode te
        JOIN Posts p ON p.Id = te.PostId
        GROUP BY te.Tag
    ),
    top_tags AS (
        SELECT
            Tag,
            tag_usage,
            ROW_NUMBER() OVER (ORDER BY tag_usage DESC)      AS tag_rank
        FROM tag_counts
        WHERE tag_usage > 1000
    )
SELECT
    tu.Id                                   AS user_id,
    tu.DisplayName,
    tu.Reputation,
    tu.rep_rank,
    COALESCE(bs.gold, 0)                     AS gold_badges,
    COALESCE(bs.silver, 0)                   AS silver_badges,
    COALESCE(bs.bronze, 0)                   AS bronze_badges,
    COALESCE(bs.total_badges, 0)             AS total_badges,
    bs.badge_names,
    COALESCE(ra.last_post_date, '1970-01-01'::timestamp) AS last_post_date,
    COALESCE(ra.question_cnt, 0)             AS recent_questions,
    COALESCE(ra.answer_cnt, 0)               AS recent_answers,
    COALESCE(ra.total_score, 0)              AS recent_total_score,
    COALESCE(vu.upvotes, 0) - COALESCE(vu.downvotes, 0) AS net_votes_on_latest_post,
    CASE WHEN COALESCE(vu.favorites, 0) > 0 THEN 'FAV' END AS favorite_flag,
    tt.Tag                                   AS top_tag_of_user,
    tt.tag_usage,
    tt.tag_rank
FROM top_users tu
LEFT JOIN badge_summary bs      ON bs.UserId = tu.Id
LEFT JOIN recent_activity ra    ON ra.UserId = tu.Id
LEFT JOIN LATERAL (
    SELECT v.*
    FROM vote_agg v
    JOIN Posts p ON p.Id = v.PostId
    WHERE p.OwnerUserId = tu.Id
    ORDER BY p.CreationDate DESC
    LIMIT 1
) vu ON TRUE
LEFT JOIN LATERAL (
    SELECT tg.Tag, tg.tag_usage, tg.tag_rank
    FROM tag_explode te
    JOIN top_tags tg ON tg.Tag = te.Tag
    WHERE te.PostId IN (
        SELECT p2.Id
        FROM Posts p2
        WHERE p2.OwnerUserId = tu.Id
        ORDER BY p2.CreationDate DESC
        LIMIT 5
    )
    ORDER BY tg.tag_usage DESC
    LIMIT 1
) tt ON TRUE
WHERE tu.rep_rank <= 100

UNION ALL

SELECT
    NULL                                    AS user_id,
    'Aggregated Summary'                    AS DisplayName,
    NULL                                    AS Reputation,
    NULL                                    AS rep_rank,
    SUM(COALESCE(bs.gold, 0))               AS gold_badges,
    SUM(COALESCE(bs.silver, 0))             AS silver_badges,
    SUM(COALESCE(bs.bronze, 0))             AS bronze_badges,
    SUM(COALESCE(bs.total_badges, 0))       AS total_badges,
    NULL                                    AS badge_names,
    MAX(ra.last_post_date)                 AS last_post_date,
    SUM(COALESCE(ra.question_cnt, 0))       AS recent_questions,
    SUM(COALESCE(ra.answer_cnt, 0))         AS recent_answers,
    SUM(COALESCE(ra.total_score, 0))        AS recent_total_score,
    NULL                                    AS net_votes_on_latest_post,
    NULL                                    AS favorite_flag,
    NULL                                    AS top_tag_of_user,
    NULL                                    AS tag_usage,
    NULL                                    AS tag_rank
FROM top_users tu
LEFT JOIN badge_summary bs      ON bs.UserId = tu.Id
LEFT JOIN recent_activity ra    ON ra.UserId = tu.Id
WHERE tu.rep_rank <= 100

INTERSECT

SELECT *
FROM (
    SELECT
        user_id, DisplayName, Reputation, rep_rank,
        gold_badges, silver_badges, bronze_badges, total_badges,
        badge_names, last_post_date, recent_questions, recent_answers,
        recent_total_score, net_votes_on_latest_post, favorite_flag,
        top_tag_of_user, tag_usage, tag_rank
    FROM (
        SELECT *
        FROM (VALUES (1)) AS dummy(col)
    ) AS placeholder
) AS dummy2

ORDER BY rep_rank NULLS LAST
LIMIT 50;
