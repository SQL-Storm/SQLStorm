WITH
user_agg AS (
    SELECT
        u.Id                                        AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, '')                    AS location,
        COALESCE(u.AboutMe, '')                     AS about_me,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_cnt,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_cnt,
        COUNT(DISTINCT b.Id)                        AS badge_cnt,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_received,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_received,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2))  AS avg_post_score,
        (SELECT AVG(a.Score)
         FROM Posts a
         WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2) AS avg_answer_score
    FROM Users u
    LEFT JOIN Posts p      ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b     ON b.UserId      = u.Id
    LEFT JOIN Votes v      ON v.PostId      = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.AboutMe
),
latest_activity AS (
    SELECT
        u.Id                                            AS user_id,
        GREATEST(
            MAX(p.LastActivityDate)                FILTER (WHERE p.LastActivityDate IS NOT NULL),
            MAX(c.CreationDate)                     FILTER (WHERE c.CreationDate IS NOT NULL)
        )                                               AS most_recent_dt
    FROM Users u
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId      = u.Id
    GROUP BY u.Id
),
user_tag_pop AS (
    SELECT
        ua.user_id,
        SUM(t.Count) FILTER (WHERE t.Count IS NOT NULL) AS total_tag_popularity,
        STRING_AGG(DISTINCT t.TagName, ', ')          AS popular_tags
    FROM user_agg ua
    LEFT JOIN Posts p
           ON p.OwnerUserId = ua.user_id
          AND p.PostTypeId = 1
    LEFT JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(
                SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2),
                '><')) AS tag
    ) AS tags ON TRUE
    LEFT JOIN Tags t ON t.TagName = tags.tag
    GROUP BY ua.user_id
),
ranked_users AS (
    SELECT
        ua.user_id,
        ua.DisplayName,
        ua.Reputation,
        ua.location,
        ua.about_me,
        ua.question_cnt,
        ua.answer_cnt,
        ua.badge_cnt,
        ua.upvote_received,
        ua.downvote_received,
        ua.avg_post_score,
        ua.avg_answer_score,
        la.most_recent_dt,
        utp.total_tag_popularity,
        utp.popular_tags,
        ROW_NUMBER() OVER (ORDER BY
            ua.Reputation DESC,
            (ua.question_cnt + ua.answer_cnt) DESC,
            ua.avg_post_score DESC NULLS LAST)                AS rank,
        SUM(ua.question_cnt + ua.answer_cnt) OVER (ORDER BY
            ua.Reputation DESC)                               AS cumulative_contributions
    FROM user_agg ua
    LEFT JOIN latest_activity la   ON la.user_id = ua.user_id
    LEFT JOIN user_tag_pop utp    ON utp.user_id = ua.user_id
    WHERE
        (ua.Reputation > 1000 OR ua.upvote_received > ua.downvote_received)
        AND (ua.location <> '' OR ua.about_me ILIKE '%SQL%')
)
SELECT
    r.rank,
    r.user_id,
    r.DisplayName,
    r.Reputation,
    r.question_cnt,
    r.answer_cnt,
    r.badge_cnt,
    r.upvote_received,
    r.downvote_received,
    r.avg_post_score,
    r.avg_answer_score,
    COALESCE(r.most_recent_dt, TIMESTAMP '1970-01-01')      AS most_recent_activity,
    r.total_tag_popularity,
    r.popular_tags,
    r.cumulative_contributions
FROM ranked_users r
WHERE r.rank <= 100

UNION ALL

SELECT
    CAST(NULL AS INTEGER) AS rank,
    CAST(NULL AS INTEGER) AS user_id,
    CAST(NULL AS TEXT) AS DisplayName,
    CAST(NULL AS INTEGER) AS Reputation,
    CAST(NULL AS INTEGER) AS question_cnt,
    CAST(NULL AS INTEGER) AS answer_cnt,
    CAST(NULL AS INTEGER) AS badge_cnt,
    CAST(NULL AS INTEGER) AS upvote_received,
    CAST(NULL AS INTEGER) AS downvote_received,
    CAST(NULL AS NUMERIC) AS avg_post_score,
    CAST(NULL AS NUMERIC) AS avg_answer_score,
    CAST(NULL AS TIMESTAMP) AS most_recent_activity,
    CAST(NULL AS BIGINT) AS total_tag_popularity,
    CAST(NULL AS TEXT) AS popular_tags,
    CAST(NULL AS BIGINT) AS cumulative_contributions
FROM (SELECT 1) AS dummy
ORDER BY rank;