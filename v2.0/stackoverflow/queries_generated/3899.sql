-- {"query": "3899.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2748} 

WITH
    rep_quartiles AS (
        SELECT
            id AS user_id,
            NTILE(4) OVER (ORDER BY reputation) AS rep_quartile
        FROM users
    ),
    user_badge_counts AS (
        SELECT
            b.userid,
            COUNT(*) FILTER (WHERE class = 1) AS gold_badges,
            COUNT(*) FILTER (WHERE class = 2) AS silver_badges,
            COUNT(*) FILTER (WHERE class = 3) AS bronze_badges,
            COUNT(*) AS total_badges
        FROM badges b
        GROUP BY b.userid
    ),
    post_metrics AS (
        SELECT
            p.owneruserid AS user_id,
            p.id AS post_id,
            p.posttypeid,
            p.score,
            p.creationdate,
            p.viewcount,
            p.favoritecount,
            p.answercount,
            p.commentcount,
            p.tags,
            ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.score DESC, p.creationdate DESC) AS rank_by_score,
            (SELECT COUNT(*) FROM votes v WHERE v.postid = p.id AND v.votetypeid = 2) AS upvote_count,
            (SELECT COUNT(*) FROM votes v WHERE v.postid = p.id AND v.votetypeid = 3) AS downvote_count,
            COALESCE(p.acceptedanswerid, -1) AS accepted_answer_indicator
        FROM posts p
        WHERE p.posttypeid = 1               -- questions only
    ),
    top_user_posts AS (
        SELECT *
        FROM post_metrics
        WHERE rank_by_score <= 3
    ),
    tag_exploded AS (
        SELECT
            owneruserid AS user_id,
            UNNEST(string_to_array(TRIM(BOTH '<>' FROM tags), '><')) AS tag_name
        FROM posts
        WHERE tags IS NOT NULL
    ),
    user_tag_counts AS (
        SELECT
            user_id,
            tag_name,
            COUNT(*) AS tag_use_count
        FROM tag_exploded
        GROUP BY user_id, tag_name
    ),
    duplicate_links AS (
        SELECT
            pl.postid,
            pl.relatedpostid,
            pl.creationdate,
            lt.name AS link_type_name
        FROM postlinks pl
        JOIN linktypes lt ON lt.id = pl.linktypeid
        WHERE lt.name = 'Duplicate'
    )
SELECT
    u.id                                   AS user_id,
    u.displayname,
    u.reputation,
    rq.rep_quartile,
    COALESCE(ubc.gold_badges, 0)           AS gold_badges,
    COALESCE(ubc.silver_badges, 0)         AS silver_badges,
    COALESCE(ubc.bronze_badges, 0)         AS bronze_badges,
    COALESCE(ubc.total_badges, 0)          AS total_badges,
    p.post_id,
    p.score,
    p.viewcount,
    p.favoritecount,
    p.answercount,
    p.commentcount,
    p.upvote_count,
    p.downvote_count,
    p.accepted_answer_indicator,
    COALESCE(p.tags, '')                   AS raw_tags,
    STRING_AGG(DISTINCT CASE WHEN t.tag_use_count > 5 THEN t.tag_name END, ',')
        FILTER (WHERE t.tag_use_count > 5) AS frequent_tags,
    dl.relatedpostid                       AS duplicate_of,
    dl.link_type_name,
    CASE
        WHEN p.score IS NULL THEN 'NoScore'
        WHEN p.score < 0 THEN 'Negative'
        WHEN p.score = 0 THEN 'Zero'
        ELSE 'Positive'
    END                                    AS score_category,
    CASE
        WHEN u.location IS NULL THEN 'UnknownLocation'
        ELSE u.location
    END                                    AS user_location,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM votes v
            WHERE v.postid = p.post_id AND v.votetypeid = 12
        ) THEN 1 ELSE 0
    END                                    AS has_spam_votes
FROM users u
LEFT JOIN rep_quartiles rq          ON rq.user_id = u.id
LEFT JOIN user_badge_counts ubc    ON ubc.userid = u.id
LEFT JOIN top_user_posts p        ON p.user_id = u.id
LEFT JOIN user_tag_counts t       ON t.user_id = u.id
LEFT JOIN duplicate_links dl      ON dl.postid = p.post_id
WHERE
    (u.reputation > (SELECT AVG(reputation) FROM users) OR u.reputation IS NULL)
    AND (p.score IS NOT NULL AND p.score > 0 OR p.score IS NULL)
GROUP BY
    u.id, u.displayname, u.reputation, rq.rep_quartile,
    ubc.gold_badges, ubc.silver_badges, ubc.bronze_badges, ubc.total_badges,
    p.post_id, p.score, p.viewcount, p.favoritecount, p.answercount,
    p.commentcount, p.upvote_count, p.downvote_count,
    p.accepted_answer_indicator, p.tags,
    dl.relatedpostid, dl.link_type_name,
    u.location
UNION ALL
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    p2.post_id,
    p2.score,
    p2.viewcount,
    p2.favoritecount,
    p2.answercount,
    p2.commentcount,
    p2.upvote_count,
    p2.downvote_count,
    p2.accepted_answer_indicator,
    p2.tags,
    NULL, NULL, NULL, NULL, NULL, NULL
FROM top_user_posts p2
WHERE p2.score IS NULL
ORDER BY user_id NULLS LAST, post_id NULLS LAST;
