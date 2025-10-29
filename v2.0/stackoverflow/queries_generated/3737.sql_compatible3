WITH
user_last_activity AS (
    SELECT
        u.Id                               AS user_id,
        MAX(p.CreationDate)                AS last_post_dt,
        MAX(c.CreationDate)                AS last_comment_dt,
        MAX(v.CreationDate)                AS last_vote_dt,
        COUNT(CASE WHEN p.Id IS NOT NULL THEN 1 END)      AS post_cnt,
        COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END)      AS comment_cnt,
        COUNT(CASE WHEN v.Id IS NOT NULL THEN 1 END)      AS vote_cnt
    FROM Users u
    LEFT JOIN Posts p     ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c  ON c.UserId = u.Id
    LEFT JOIN Votes v     ON v.UserId = u.Id
    GROUP BY u.Id
),

user_badge_score AS (
    SELECT
        b.UserId                                 AS user_id,
        SUM(
            CASE b.Class
                WHEN 1 THEN 1000
                WHEN 2 THEN 500
                WHEN 3 THEN 100
                ELSE 0
            END
        )                                        AS badge_score,
        STRING_AGG(DISTINCT b.Name, ', ')        AS badge_list
    FROM Badges b
    GROUP BY b.UserId
),

tag_stats AS (
    SELECT
        t.Id                                     AS tag_id,
        t.TagName,
        t.Count                                  AS tag_total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_cnt,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_cnt,
        MAX(
            (SELECT MAX(p2.CreationDate)
             FROM Posts p2
             WHERE p2.ParentId = p.Id
               AND p2.PostTypeId = 2)
        )                                        AS latest_answer_dt
    FROM Tags t
    LEFT JOIN Posts p
        ON p.Tags LIKE '%' || t.TagName || '%'
        AND p.PostTypeId IN (1,2)
    GROUP BY t.Id, t.TagName, t.Count
),

post_enriched AS (
    SELECT
        p.Id                                         AS post_id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.Tags, '')                         AS tags_raw,
        NULLIF(SUBSTRING(p.Tags FROM '<([^>]+)>'), '') AS first_tag,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS upvote_cnt,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS downvote_cnt,
        MAX(
            CASE 
                WHEN ph.PostHistoryTypeId = 10 THEN
                    NULLIF(
                        CAST(ph.Comment AS VARCHAR),
                        ''
                    )
                ELSE NULL
            END
        ) OVER (PARTITION BY p.Id)                 AS close_reason_text,
        MAX(
            CASE 
                WHEN ph.PostHistoryTypeId = 10 THEN
                    NULLIF(
                        REGEXP_REPLACE(ph.Comment, '.*"CloseReasonId"\s*:\s*"*([^",}]*)".*', '\1'),
                        ''
                    )
                ELSE NULL
            END
        ) OVER (PARTITION BY p.Id)                 AS close_reason_id,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM PostHistory ph2
                WHERE ph2.PostId = p.Id
                  AND ph2.PostHistoryTypeId IN (4,5,6)
                  AND ph2.CreationDate > p.CreationDate
            ) THEN 1 ELSE 0
        END                                          AS has_edits
    FROM Posts p
    LEFT JOIN Votes v
        ON v.PostId = p.Id
    LEFT JOIN PostHistory ph
        ON ph.PostId = p.Id
    WHERE p.PostTypeId IN (1,2)
),

duplicate_links AS (
    SELECT
        pl.PostId          AS source_post_id,
        pl.RelatedPostId   AS target_post_id,
        pl.CreationDate    AS link_dt
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),

user_profile AS (
    SELECT
        u.Id                            AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ua.last_post_dt, CAST('1970-01-01' AS TIMESTAMP))    AS last_post_dt,
        COALESCE(ua.last_comment_dt, CAST('1970-01-01' AS TIMESTAMP)) AS last_comment_dt,
        COALESCE(ua.last_vote_dt, CAST('1970-01-01' AS TIMESTAMP))    AS last_vote_dt,
        ua.post_cnt,
        ua.comment_cnt,
        ua.vote_cnt,
        COALESCE(ub.badge_score,0)                AS badge_score,
        ub.badge_list,
        (CASE WHEN EXISTS (
            SELECT 1 FROM duplicate_links dl
            JOIN Posts p ON p.Id = dl.source_post_id
            WHERE p.OwnerUserId = u.Id
        ) THEN 1 ELSE 0 END)                       AS is_duplicate_author
    FROM Users u
    LEFT JOIN user_last_activity ua ON ua.user_id = u.Id
    LEFT JOIN user_badge_score ub    ON ub.user_id = u.Id
),

monthly_top_users AS (
    SELECT
        up.user_id,
        up.DisplayName,
        DATE_TRUNC('month', up.last_post_dt) AS month,
        up.post_cnt,
        ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', up.last_post_dt)
                           ORDER BY up.post_cnt DESC, up.badge_score DESC) AS rn
    FROM user_profile up
    WHERE up.last_post_dt > CAST('2020-01-01' AS TIMESTAMP)
)

SELECT
    'USER_PROFILE'        AS result_type,
    up.user_id,
    up.DisplayName,
    up.Reputation,
    up.last_post_dt,
    up.last_comment_dt,
    up.last_vote_dt,
    up.post_cnt,
    up.comment_cnt,
    up.vote_cnt,
    up.badge_score,
    up.badge_list,
    up.is_duplicate_author,
    CAST(NULL AS INTEGER)                  AS tag_id,
    CAST(NULL AS VARCHAR)                  AS tag_name,
    CAST(NULL AS INTEGER)                  AS question_cnt,
    CAST(NULL AS INTEGER)                  AS answer_cnt,
    CAST(NULL AS TIMESTAMP)                AS latest_answer_dt,
    CAST(NULL AS INTEGER)                  AS post_id,
    CAST(NULL AS INTEGER)                  AS post_type,
    CAST(NULL AS VARCHAR)                  AS title,
    CAST(NULL AS INTEGER)                  AS upvote_cnt,
    CAST(NULL AS INTEGER)                  AS downvote_cnt,
    CAST(NULL AS INTEGER)                  AS close_reason_id,
    CAST(NULL AS INTEGER)                  AS has_edits
FROM user_profile up

UNION ALL

SELECT
    'MONTHLY_TOP'          AS result_type,
    mt.user_id,
    mt.DisplayName,
    CAST(NULL AS INTEGER)                  AS Reputation,
    mt.month               AS last_post_dt,
    CAST(NULL AS TIMESTAMP)                AS last_comment_dt,
    CAST(NULL AS TIMESTAMP)                AS last_vote_dt,
    mt.post_cnt,
    CAST(NULL AS INTEGER)                  AS comment_cnt,
    CAST(NULL AS INTEGER)                  AS vote_cnt,
    CAST(NULL AS INTEGER)                  AS badge_score,
    CAST(NULL AS VARCHAR)                  AS badge_list,
    CAST(NULL AS INTEGER)                  AS is_duplicate_author,
    CAST(NULL AS INTEGER)                  AS tag_id,
    CAST(NULL AS VARCHAR)                  AS tag_name,
    CAST(NULL AS INTEGER)                  AS question_cnt,
    CAST(NULL AS INTEGER)                  AS answer_cnt,
    CAST(NULL AS TIMESTAMP)                AS latest_answer_dt,
    CAST(NULL AS INTEGER)                  AS post_id,
    CAST(NULL AS INTEGER)                  AS post_type,
    CAST(NULL AS VARCHAR)                  AS title,
    CAST(NULL AS INTEGER)                  AS upvote_cnt,
    CAST(NULL AS INTEGER)                  AS downvote_cnt,
    CAST(NULL AS INTEGER)                  AS close_reason_id,
    CAST(NULL AS INTEGER)                  AS has_edits
FROM monthly_top_users mt
WHERE mt.rn <= 5

ORDER BY result_type, last_post_dt DESC, post_cnt DESC;