WITH recent_questions AS (
    SELECT
        id,
        owneruserid,
        tags,
        score,
        creationdate
    FROM posts
    WHERE posttypeid = 1
      AND creationdate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
question_tags AS (
    SELECT
        rq.id            AS question_id,
        rq.owneruserid   AS user_id,
        t.tag,
        rq.score
    FROM recent_questions rq,
    LATERAL (
        SELECT unnest(
            string_to_array(
                substring(rq.tags FROM 2 FOR (length(rq.tags) - 2)),
                '><'
            )
        ) AS tag
    ) t
),
user_tag_scores AS (
    SELECT
        user_id,
        tag,
        COUNT(*)    AS questions_asked,
        SUM(score) AS total_score
    FROM question_tags
    GROUP BY user_id, tag
),
user_badge_counts AS (
    SELECT
        userid,
        COUNT(CASE WHEN class = 1 THEN 1 END) AS gold,
        COUNT(CASE WHEN class = 2 THEN 1 END) AS silver,
        COUNT(CASE WHEN class = 3 THEN 1 END) AS bronze
    FROM badges
    WHERE date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY userid
),
user_activity AS (
    SELECT
        u.id,
        u.displayname,
        u.reputation,
        COALESCE(ub.gold,   0) AS gold_badges,
        COALESCE(ub.silver, 0) AS silver_badges,
        COALESCE(ub.bronze, 0) AS bronze_badges,
        uts.tag,
        uts.questions_asked,
        uts.total_score,
        ROW_NUMBER() OVER (
            PARTITION BY uts.tag
            ORDER BY uts.total_score DESC
        ) AS rank_within_tag
    FROM users u
    LEFT JOIN user_badge_counts ub
        ON ub.userid = u.id
    JOIN user_tag_scores uts
        ON uts.user_id = u.id
)
SELECT
    id,
    displayname,
    reputation,
    gold_badges,
    silver_badges,
    bronze_badges,
    tag,
    questions_asked,
    total_score,
    rank_within_tag
FROM user_activity
WHERE rank_within_tag <= 3
GROUP BY
    id,
    displayname,
    reputation,
    gold_badges,
    silver_badges,
    bronze_badges,
    tag,
    questions_asked,
    total_score,
    rank_within_tag
ORDER BY tag, rank_within_tag;