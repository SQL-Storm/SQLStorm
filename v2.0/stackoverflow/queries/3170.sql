-- {"query": "3170.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2226}
WITH
    user_stats AS (
        SELECT
            u.id,
            u.displayname,
            u.reputation,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_cnt,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_cnt,
            COALESCE(SUM(p.score), 0) AS total_score,
            MAX(p.creationdate) AS last_post_dt
        FROM users u
        LEFT JOIN posts p ON p.owneruserid = u.id
        GROUP BY u.id, u.displayname, u.reputation
    ),

    top_tags AS (
        SELECT
            t.tagname,
            COUNT(*) AS usage_cnt,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
        FROM posts p
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(trim(both '<>' FROM p.tags), '><')) AS tag
        ) AS tags
        JOIN tags t ON t.tagname = tags.tag
        WHERE p.posttypeid = 1
        GROUP BY t.tagname
        HAVING COUNT(*) > 100
    ),

    badge_stats AS (
        SELECT
            b.userid,
            SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
            COUNT(*) FILTER (WHERE b.tagbased = TRUE) AS tag_based_cnt
        FROM badges b
        GROUP BY b.userid
    ),

    vote_stats AS (
        SELECT
            v.userid,
            SUM(CASE WHEN vt.id = 2 THEN 1 ELSE 0 END) AS upvotes_given,
            SUM(CASE WHEN vt.id = 3 THEN 1 ELSE 0 END) AS downvotes_given,
            SUM(CASE WHEN vt.id = 5 THEN 1 ELSE 0 END) AS favorites_given
        FROM votes v
        JOIN votetypes vt ON vt.id = v.votetypeid
        WHERE v.userid IS NOT NULL
        GROUP BY v.userid
    ),

    recent_closed AS (
        SELECT
            p.id,
            p.title,
            p.tags,
            ph.creationdate AS closed_dt,
            CAST(ph.comment AS INTEGER) AS close_reason_id,
            COALESCE(crt.name, 'Unknown') AS close_reason_name,
            p.owneruserid
        FROM posts p
        JOIN posthistory ph
              ON ph.postid = p.id
             AND ph.posthistorytypeid = 10
        LEFT JOIN closereasontypes crt
               ON crt.id = CAST(ph.comment AS INTEGER)
        WHERE p.posttypeid = 1
          AND ph.creationdate >= (CAST('2024-10-01' AS DATE) - INTERVAL '30 days')
    ),

    user_latest_closed AS (
        SELECT DISTINCT ON (rc.owneruserid)
            rc.owneruserid,
            rc.title,
            rc.close_reason_name
        FROM recent_closed rc
        ORDER BY rc.owneruserid, rc.closed_dt DESC
    )

SELECT
    us.id,
    us.displayname,
    us.reputation,
    us.question_cnt,
    us.answer_cnt,
    us.total_score,
    bs.gold_cnt,
    bs.silver_cnt,
    bs.bronze_cnt,
    bs.tag_based_cnt,
    vs.upvotes_given,
    vs.downvotes_given,
    vs.favorites_given,
    ulc.title AS recent_closed_title,
    ulc.close_reason_name AS recent_closed_reason,
    STRING_AGG(DISTINCT tt.tagname, ', ') FILTER (WHERE tt.rn <= 5) AS top_tags_used
FROM user_stats us
LEFT JOIN badge_stats bs ON bs.userid = us.id
LEFT JOIN vote_stats vs ON vs.userid = us.id
LEFT JOIN user_latest_closed ulc ON ulc.owneruserid = us.id
LEFT JOIN LATERAL (
    SELECT tt.tagname, tt.rn
    FROM top_tags tt
    WHERE EXISTS (
        SELECT 1
        FROM posts p
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(trim(both '<>' FROM p.tags), '><')) AS tag
        ) AS tags
        WHERE p.owneruserid = us.id
          AND p.posttypeid = 1
          AND tags.tag = tt.tagname
    )
) tt ON true
GROUP BY
    us.id, us.displayname, us.reputation,
    us.question_cnt, us.answer_cnt, us.total_score,
    bs.gold_cnt, bs.silver_cnt, bs.bronze_cnt, bs.tag_based_cnt,
    vs.upvotes_given, vs.downvotes_given, vs.favorites_given,
    ulc.title, ulc.close_reason_name
ORDER BY us.total_score DESC
LIMIT 100;