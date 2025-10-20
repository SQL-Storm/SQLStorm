-- {"query": "39084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2672} 

WITH question_tags AS (
    SELECT
        p.Id AS question_id,
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        ) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_stats AS (
    SELECT
        qt.tag,
        COUNT(*)                        AS question_count,
        AVG(p.Score)                    AS avg_score,
        SUM(p.ViewCount)::bigint        AS total_views
    FROM question_tags qt
    JOIN Posts p ON p.Id = qt.question_id
    GROUP BY qt.tag
    HAVING COUNT(*) > 100
),
user_badges AS (
    SELECT
        b.UserId                           AS user_id,
        COUNT(*)                           AS badge_count,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),
user_activity AS (
    SELECT
        u.Id                                             AS user_id,
        u.DisplayName,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)         AS questions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)         AS answers,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)     AS avg_answer_score,
        SUM(
            CASE
                WHEN v.VoteTypeId = 2 THEN  1
                WHEN v.VoteTypeId = 3 THEN -1
                ELSE 0
            END
        )                                                AS vote_delta
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT
    ts.tag,
    ts.question_count,
    ts.avg_score,
    ts.total_views,
    ua.DisplayName        AS top_user,
    ua.questions,
    ua.answers,
    ua.avg_answer_score,
    ua.vote_delta,
    COALESCE(ub.badge_count, 0)   AS badge_count,
    COALESCE(ub.gold_badges,  0)  AS gold_badges,
    COALESCE(ub.silver_badges,0)  AS silver_badges,
    COALESCE(ub.bronze_badges,0)  AS bronze_badges
FROM tag_stats ts
JOIN question_tags qt   ON qt.tag = ts.tag
JOIN Posts p            ON p.Id = qt.question_id
JOIN user_activity ua   ON ua.user_id = p.OwnerUserId
LEFT JOIN user_badges ub ON ub.user_id = ua.user_id
ORDER BY ts.total_views DESC, ua.answers DESC
LIMIT 50;
