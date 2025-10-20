WITH question_tags AS (
    SELECT
        p.Id AS question_id,
        UNNEST(
            STRING_TO_ARRAY(
                SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)),
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
        SUM(p.ViewCount)                AS total_views
    FROM question_tags qt
    JOIN Posts p ON p.Id = qt.question_id
    GROUP BY qt.tag
    HAVING COUNT(*) > 100
),
user_badges AS (
    SELECT
        b.UserId                           AS user_id,
        COUNT(*)                           AS badge_count,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),
user_activity AS (
    SELECT
        u.Id                                             AS user_id,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)         AS questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)         AS answers,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)     AS avg_answer_score,
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
GROUP BY
    ts.tag,
    ts.question_count,
    ts.avg_score,
    ts.total_views,
    ua.DisplayName,
    ua.questions,
    ua.answers,
    ua.avg_answer_score,
    ua.vote_delta,
    ub.badge_count,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges
ORDER BY ts.total_views DESC, ua.answers DESC
LIMIT 50;