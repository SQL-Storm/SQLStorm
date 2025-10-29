WITH
user_stats AS (
    SELECT
        u.id                                     AS user_id,
        u.displayname,
        u.reputation,
        COUNT(p.id)               FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
        COUNT(p.id)               FILTER (WHERE p.posttypeid = 1) AS question_cnt,
        AVG(p.score)              FILTER (WHERE p.posttypeid = 2) AS avg_answer_score,
        MAX(p.creationdate)                              AS last_post_dt
    FROM users u
    LEFT JOIN posts p
           ON p.owneruserid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),
badge_stats AS (
    SELECT
        b.userid           AS user_id,
        COUNT(*)           AS total_badges,
        COUNT(*) FILTER (WHERE b.class = 1) AS gold_badges,
        MIN(b.date)        AS first_badge_dt
    FROM badges b
    GROUP BY b.userid
),
recent_votes AS (
    SELECT
        v.userid           AS user_id,
        COUNT(*)           AS recent_vote_cnt
    FROM votes v
    WHERE v.creationdate >= CAST(CAST('2024-10-01' AS date) - INTERVAL '30 days' AS date)
    GROUP BY v.userid
),
latest_closed AS (
    SELECT
        ph.postid          AS post_id,
        MAX(ph.creationdate) AS closed_dt
    FROM posthistory ph
    WHERE ph.posthistorytypeid = 10
    GROUP BY ph.postid
),
duplicate_links AS (
    SELECT
        pl.postid           AS post_id,
        pl.relatedpostid    AS dup_of_post_id
    FROM postlinks pl
    WHERE pl.linktypeid = 3
),
top_tag_posts AS (
    SELECT
        p.id,
        p.title,
        t.tag,
        p.score,
        ROW_NUMBER() OVER (PARTITION BY t.tag
                           ORDER BY p.score DESC) AS rn
    FROM posts p
    CROSS JOIN LATERAL (
      SELECT unnest(string_to_array(substring(p.tags FROM 2 FOR length(p.tags)-2), '><')) AS tag
    ) t
    WHERE p.posttypeid = 1
      AND p.tags IS NOT NULL
),
tag_rankings AS (
    SELECT
        tag,
        id    AS top_post_id,
        title AS top_post_title,
        score AS top_score
    FROM top_tag_posts
    WHERE rn = 1
),
enriched_users AS (
    SELECT
        us.user_id,
        us.displayname,
        us.reputation,
        us.answer_cnt,
        us.question_cnt,
        us.avg_answer_score,
        us.last_post_dt,
        COALESCE(bs.total_badges,0)      AS total_badges,
        COALESCE(bs.gold_badges,0)       AS gold_badges,
        bs.first_badge_dt,
        COALESCE(rv.recent_vote_cnt,0)   AS recent_votes,
        lc.closed_dt,
        dl.dup_of_post_id
    FROM user_stats us
    LEFT JOIN badge_stats bs      ON bs.user_id = us.user_id
    LEFT JOIN recent_votes rv    ON rv.user_id = us.user_id
    LEFT JOIN latest_closed lc   ON lc.post_id = us.user_id
    LEFT JOIN duplicate_links dl ON dl.post_id = us.user_id
),
user_activity_lag AS (
    SELECT
        eu.user_id,
        eu.displayname,
        eu.reputation,
        eu.answer_cnt,
        eu.question_cnt,
        eu.avg_answer_score,
        eu.last_post_dt,
        eu.total_badges,
        eu.gold_badges,
        eu.first_badge_dt,
        eu.recent_votes,
        eu.closed_dt,
        eu.dup_of_post_id,
        COALESCE(EXTRACT(day FROM (CAST('2024-10-01 12:34:56' AS timestamp) - eu.last_post_dt)), NULL) AS days_since_last_post
    FROM enriched_users eu
),
ranked_users AS (
    SELECT
        ual.user_id,
        ual.displayname,
        ual.reputation,
        ual.answer_cnt,
        ual.question_cnt,
        ual.avg_answer_score,
        ual.last_post_dt,
        ual.total_badges,
        ual.gold_badges,
        ual.first_badge_dt,
        ual.recent_votes,
        ual.closed_dt,
        ual.dup_of_post_id,
        ual.days_since_last_post,
        ROW_NUMBER() OVER (ORDER BY ual.reputation DESC, ual.gold_badges DESC) AS rank_by_rep
    FROM user_activity_lag ual
    WHERE ual.reputation > 15000
       OR ual.gold_badges >= 1
)
SELECT
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.answer_cnt,
    ru.question_cnt,
    ROUND(CAST(ru.avg_answer_score AS numeric),2)      AS avg_answer_score,
    ru.total_badges,
    ru.gold_badges,
    ru.recent_votes,
    CASE WHEN ru.closed_dt IS NOT NULL THEN 'Closed' ELSE 'Active' END AS status,
    CASE WHEN ru.dup_of_post_id IS NOT NULL THEN 'HasDuplicate' ELSE 'Unique' END AS dup_flag,
    ru.days_since_last_post,
    ru.rank_by_rep
FROM ranked_users ru
UNION ALL
SELECT
    NULL                      AS user_id,
    '-- Tag Summary --'       AS displayname,
    NULL                      AS reputation,
    NULL                      AS answer_cnt,
    NULL                      AS question_cnt,
    NULL                      AS avg_answer_score,
    NULL                      AS total_badges,
    NULL                      AS gold_badges,
    NULL                      AS recent_votes,
    ('Tag: ' || tr.tag)       AS status,
    ('Score:' || CAST(tr.top_score AS text)) AS dup_flag,
    NULL                      AS days_since_last_post,
    NULL                      AS rank_by_rep
FROM tag_rankings tr
ORDER BY status DESC, dup_flag DESC
LIMIT 10;