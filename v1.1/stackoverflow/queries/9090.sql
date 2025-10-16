WITH recent_activity AS (
    SELECT
        p.id,
        p.title,
        p.owneruserid,
        p.score,
        p.creationdate,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate DESC) AS rn,
        COUNT(c.id) OVER (PARTITION BY p.id) AS comment_count,
        COALESCE(
            (SELECT COUNT(*) 
               FROM votes v 
              WHERE v.postid = p.id 
                AND v.votetypeid = 2), 
            0
        ) AS upvote_count
    FROM posts p
    LEFT JOIN comments c
      ON c.postid = p.id
    WHERE p.creationdate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH
),
user_badges AS (
    SELECT
        userid,
        STRING_AGG(name, ',' ORDER BY date DESC) AS badges
    FROM badges
    GROUP BY userid
),
tag_usage AS (
    SELECT
        t.tag,
        COUNT(DISTINCT p.id) AS question_count
    FROM posts p,
    LATERAL (
      SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.tags FROM 2 FOR CHAR_LENGTH(p.tags) - 2), '><')) AS tag
    ) t
    WHERE p.posttypeid = 1
    GROUP BY t.tag
),
top_tags AS (
    SELECT *
      FROM tag_usage
     WHERE question_count > (SELECT AVG(question_count) FROM tag_usage)
     ORDER BY question_count DESC
     LIMIT 5
),
combined_data AS (
    SELECT
        ra.id,
        ra.title,
        ra.owneruserid,
        ra.score,
        ra.comment_count,
        ra.upvote_count,
        CAST(ub.badges AS VARCHAR) AS badge_list
    FROM recent_activity ra
    LEFT JOIN user_badges ub
      ON ub.userid = ra.owneruserid
   WHERE ra.rn <= 3

    UNION ALL

    SELECT
        NULL    AS id,
        t.tag   AS title,
        NULL    AS owneruserid,
        t.question_count AS score,
        NULL    AS comment_count,
        NULL    AS upvote_count,
        NULL    AS badge_list
    FROM top_tags t
),
high_intersection AS (
    SELECT id
      FROM recent_activity
     WHERE score > 10
    INTERSECT
    SELECT id
      FROM recent_activity
     WHERE comment_count > 5
),
low_activity AS (
    SELECT id
      FROM recent_activity
     WHERE score < 0
    EXCEPT
    SELECT id
      FROM recent_activity
     WHERE comment_count >= 1
)
SELECT
    cd.id,
    cd.title,
    cd.owneruserid,
    cd.score,
    cd.comment_count,
    cd.upvote_count,
    cd.badge_list,
    ROUND(CAST(cd.score AS NUMERIC) / NULLIF(cd.comment_count, 0), 2) AS score_per_comment,
    CASE
        WHEN cd.badge_list IS NULL THEN 'No Badges'
        ELSE SUBSTRING(cd.badge_list FROM 1 FOR 50)
    END AS badge_excerpt,
    CASE
        WHEN hi.id IS NOT NULL THEN 'HighActivity'
        WHEN la.id IS NOT NULL THEN 'LowActivity'
        ELSE 'Normal'
    END AS activity_flag
FROM combined_data cd
LEFT JOIN high_intersection hi
  ON cd.id = hi.id
LEFT JOIN low_activity la
  ON cd.id = la.id
ORDER BY COALESCE(CAST(cd.score AS NUMERIC) / NULLIF(cd.comment_count, 0), 0) DESC
OFFSET 0 LIMIT 100;