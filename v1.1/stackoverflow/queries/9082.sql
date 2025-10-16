WITH
    user_activity AS (
        SELECT
            u.Id AS user_id,
            u.DisplayName AS display_name,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_count,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_count,
            ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS activity_rank
        FROM Users u
        LEFT JOIN Posts p
            ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName
    ),
    top_posts AS (
        SELECT
            p.Id AS post_id,
            p.OwnerUserId AS user_id,
            p.Title,
            p.Score,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS post_rank
        FROM Posts p
        WHERE p.PostTypeId IN (1, 2)
    ),
    post_metrics AS (
        SELECT
            tp.post_id,
            AVG(c.Score) AS avg_comment_score,
            SUM(v.BountyAmount) AS total_bounty
        FROM top_posts tp
        LEFT JOIN Comments c
            ON c.PostId = tp.post_id
        LEFT JOIN Votes v
            ON v.PostId = tp.post_id
           AND v.VoteTypeId IN (8, 9)
        GROUP BY tp.post_id
    ),
    frequent_tags AS (
        SELECT
            tag,
            COUNT(*) AS tag_usage
        FROM (
            SELECT
                UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
            FROM Posts p
            WHERE p.PostTypeId = 1
              AND p.Tags IS NOT NULL
        ) t
        GROUP BY tag
        HAVING COUNT(*) > 100
    ),
    gold_badges AS (
        SELECT
            b.UserId,
            COUNT(*) AS gold_count,
            STRING_AGG(b.Name, ', ') AS gold_badge_names
        FROM Badges b
        WHERE b.Class = 1
        GROUP BY b.UserId
    )

SELECT
    ua.display_name,
    ua.activity_rank,
    ua.question_count,
    ua.answer_count,
    tp.post_id,
    tp.Title,
    tp.Score,
    pm.avg_comment_score,
    COALESCE(pm.total_bounty, 0) AS total_bounty,
    fb.tag AS frequent_tag,
    fb.tag_usage,
    gb.gold_count,
    gb.gold_badge_names,
    CASE
        WHEN ua.question_count = 0 THEN NULL
        ELSE ROUND(CAST(tp.Score AS NUMERIC) / ua.question_count, 2)
    END AS score_per_question
FROM user_activity ua
JOIN top_posts tp
    ON tp.user_id = ua.user_id
   AND tp.post_rank <= 3
LEFT JOIN post_metrics pm
    ON pm.post_id = tp.post_id
LEFT JOIN LATERAL (
    SELECT
        f.tag,
        f.tag_usage
    FROM frequent_tags f
    WHERE f.tag = ANY (
        STRING_TO_ARRAY(
            TRIM(BOTH '<>' FROM (
                SELECT Tags
                FROM Posts
                WHERE Id = tp.post_id
            )),
            '><'
        )
    )
    LIMIT 1
) fb ON TRUE
LEFT JOIN gold_badges gb
    ON gb.UserId = ua.user_id
WHERE ua.activity_rank <= 50

UNION ALL

SELECT
    u.DisplayName AS display_name,
    CAST(NULL AS INTEGER) AS activity_rank,
    CAST(NULL AS INTEGER) AS question_count,
    CAST(NULL AS INTEGER) AS answer_count,
    CAST(NULL AS INTEGER) AS post_id,
    CAST(NULL AS VARCHAR) AS Title,
    CAST(NULL AS INTEGER) AS Score,
    CAST(NULL AS NUMERIC) AS avg_comment_score,
    CAST(NULL AS NUMERIC) AS total_bounty,
    CAST(NULL AS VARCHAR) AS frequent_tag,
    CAST(NULL AS INTEGER) AS tag_usage,
    CAST(NULL AS INTEGER) AS gold_count,
    CAST(NULL AS VARCHAR) AS gold_badge_names,
    CAST(NULL AS NUMERIC) AS score_per_question
FROM Users u
WHERE NOT EXISTS (
    SELECT 1
    FROM Posts p
    WHERE p.OwnerUserId = u.Id
)

EXCEPT

SELECT
    ua.display_name,
    ua.activity_rank,
    ua.question_count,
    ua.answer_count,
    CAST(NULL AS INTEGER) AS post_id,
    CAST(NULL AS VARCHAR) AS Title,
    CAST(NULL AS INTEGER) AS Score,
    CAST(NULL AS NUMERIC) AS avg_comment_score,
    CAST(NULL AS NUMERIC) AS total_bounty,
    CAST(NULL AS VARCHAR) AS frequent_tag,
    CAST(NULL AS INTEGER) AS tag_usage,
    CAST(NULL AS INTEGER) AS gold_count,
    CAST(NULL AS VARCHAR) AS gold_badge_names,
    CAST(NULL AS NUMERIC) AS score_per_question
FROM user_activity ua
WHERE ua.activity_rank <= 5

ORDER BY
    activity_rank NULLS LAST,
    display_name;