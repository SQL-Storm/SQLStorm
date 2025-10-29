-- {"query": "3864.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1672} 

/* Benchmark query: complex analysis of user activity, post performance, tags and badges */
WITH
    /* 1. Base user metrics */
    usr_metrics AS (
        SELECT
            u.Id                               AS user_id,
            u.DisplayName                      AS display_name,
            u.Reputation,
            u.CreationDate                     AS user_created,
            COUNT(p.Id)                         FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
            COUNT(p.Id)                         FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
            SUM(CASE WHEN p.PostTypeId = 2 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS accepted_answer_cnt,
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)                       AS avg_answer_score,
            MAX(p.CreationDate)               FILTER (WHERE p.PostTypeId = 1) AS last_question_date,
            MAX(p.CreationDate)               FILTER (WHERE p.PostTypeId = 2) AS last_answer_date
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    ),

    /* 2. Badge aggregation (including users with zero badges) */
    badge_stats AS (
        SELECT
            b.UserId                     AS user_id,
            COUNT(*)                     AS total_badges,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
            STRING_AGG(DISTINCT b.Name, '; ') FILTER (WHERE b.Class = 1) AS gold_badge_names
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* 3. Tag involvement per user (derived from their questions) */
    user_tags AS (
        SELECT
            p.OwnerUserId                         AS user_id,
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag,
            COUNT(*)                              AS tag_uses
        FROM Posts p
        WHERE p.PostTypeId = 1                     -- only questions have tags
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, tag
    ),

    /* 4. Top tags overall (to compare with user tag usage) */
    top_tags AS (
        SELECT
            t.TagName,
            t.Count   AS global_tag_count,
            ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
        FROM Tags t
        WHERE t.IsModeratorOnly = 0
    ),

    /* 5. Recent activity indicator (questions asked in last 90 days) */
    recent_activity AS (
        SELECT
            u.Id                               AS user_id,
            BOOL_OR(p.CreationDate >= CURRENT_DATE - INTERVAL '90 days' AND p.PostTypeId = 1) AS asked_recent_question,
            BOOL_OR(p.CreationDate >= CURRENT_DATE - INTERVAL '90 days' AND p.PostTypeId = 2) AS gave_recent_answer
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id
    ),

    /* 6. Correlated subquery: average score of a user’s answers compared to the global answer average */
    answer_score_comparison AS (
        SELECT
            u.Id                                   AS user_id,
            COALESCE((
                SELECT AVG(p2.Score)::numeric
                FROM Posts p2
                WHERE p2.OwnerUserId = u.Id
                  AND p2.PostTypeId = 2
            ), 0)                                  AS user_avg_answer_score,
            (SELECT AVG(p3.Score)::numeric
             FROM Posts p3
             WHERE p3.PostTypeId = 2)               AS global_avg_answer_score,
            CASE
                WHEN (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.PostTypeId = 2) = 0 THEN NULL
                ELSE (COALESCE((
                        SELECT AVG(p2.Score)
                        FROM Posts p2
                        WHERE p2.OwnerUserId = u.Id
                          AND p2.PostTypeId = 2),0) /
                      (SELECT AVG(p3.Score)
                        FROM Posts p3
                        WHERE p3.PostTypeId = 2))
            END                                    AS score_ratio
        FROM Users u
    ),

    /* 7. Union of users with and without recent activity (set operator) */
    combined_activity AS (
        SELECT user_id, asked_recent_question, gave_recent_answer FROM recent_activity
        UNION ALL
        SELECT u.Id, FALSE, FALSE
        FROM Users u
        WHERE NOT EXISTS (SELECT 1 FROM recent_activity ra WHERE ra.user_id = u.Id)
    )

SELECT
    um.user_id,
    um.display_name,
    um.reputation,
    um.question_cnt,
    um.answer_cnt,
    um.accepted_answer_cnt,
    ROUND(um.avg_answer_score,2)                                    AS avg_answer_score,
    bs.total_badges,
    bs.gold_badges,
    bs.silver_badges,
    bs.bronze_badges,
    bs.gold_badge_names,
    ca.asked_recent_question,
    ca.gave_recent_answer,
    asc.user_avg_answer_score,
    asc.global_avg_answer_score,
    ROUND(asc.score_ratio,3)                                        AS answer_score_ratio,
    /* Top 3 tags used by the user with global rank */
    STRING_AGG(
        CONCAT(ut.tag, ' (', ut.tag_uses, ' uses, global rank ', COALESCE(tt.tag_rank, -1), ')'),
        '; '
        ORDER BY ut.tag_uses DESC
    ) FILTER (WHERE ut.tag IS NOT NULL)                             AS top_user_tags
FROM usr_metrics um
LEFT JOIN badge_stats bs           ON bs.user_id = um.user_id
LEFT JOIN combined_activity ca    ON ca.user_id = um.user_id
LEFT JOIN answer_score_comparison asc ON asc.user_id = um.user_id
LEFT JOIN LATERAL (
    SELECT *
    FROM user_tags ut
    WHERE ut.user_id = um.user_id
    ORDER BY ut.tag_uses DESC
    LIMIT 3
) ut ON TRUE
LEFT JOIN top_tags tt            ON tt.TagName = ut.tag
GROUP BY
    um.user_id, um.display_name, um.reputation,
    um.question_cnt, um.answer_cnt, um.accepted_answer_cnt,
    um.avg_answer_score, bs.total_badges, bs.gold_badges,
    bs.silver_badges, bs.bronze_badges, bs.gold_badge_names,
    ca.asked_recent_question, ca.gave_recent_answer,
    asc.user_avg_answer_score, asc.global_avg_answer_score,
    asc.score_ratio
HAVING
    um.reputation > 5000
    AND um.answer_cnt >= 10
    AND (bs.gold_badges > 0 OR bs.silver_badges > 5)
    AND (ca.asked_recent_question OR ca.gave_recent_answer)
ORDER BY um.reputation DESC, um.answer_cnt DESC
LIMIT 100;
