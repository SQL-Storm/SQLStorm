-- {"query": "3608.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2378}
WITH user_stats AS (
    SELECT 
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        COALESCE(p.post_cnt,0)          AS post_cnt,
        COALESCE(a.answer_cnt,0)       AS answer_cnt,
        COALESCE(c.comment_cnt,0)      AS comment_cnt,
        COALESCE(b.badge_cnt,0)        AS badge_cnt,
        COALESCE(v.vote_score,0)       AS vote_score,
        COALESCE(v.vote_up,0)          AS vote_up,
        COALESCE(v.vote_down,0)        AS vote_down
    FROM users u
    LEFT JOIN (
        SELECT owneruserid, COUNT(*) AS post_cnt
        FROM posts
        WHERE owneruserid IS NOT NULL
        GROUP BY owneruserid
    ) p  ON p.owneruserid = u.id
    LEFT JOIN (
        SELECT owneruserid, COUNT(*) AS answer_cnt
        FROM posts
        WHERE posttypeid = 2 AND owneruserid IS NOT NULL
        GROUP BY owneruserid
    ) a  ON a.owneruserid = u.id
    LEFT JOIN (
        SELECT userid, COUNT(*) AS comment_cnt
        FROM comments
        WHERE userid IS NOT NULL
        GROUP BY userid
    ) c  ON c.userid = u.id
    LEFT JOIN (
        SELECT userid, COUNT(*) AS badge_cnt
        FROM badges
        WHERE userid IS NOT NULL
        GROUP BY userid
    ) b  ON b.userid = u.id
    LEFT JOIN (
        SELECT 
            userid,
            SUM(CASE WHEN votetypeid = 2 THEN 1 ELSE 0 END) AS vote_up,
            SUM(CASE WHEN votetypeid = 3 THEN 1 ELSE 0 END) AS vote_down,
            SUM(CASE 
                    WHEN votetypeid = 2 THEN 1 
                    WHEN votetypeid = 3 THEN -1 
                    ELSE 0 
                END)                              AS vote_score
        FROM votes
        GROUP BY userid
    ) v ON v.userid = u.id
),
user_ranks AS (
    SELECT 
        us.id,
        us.displayname,
        us.reputation,
        us.creationdate,
        us.post_cnt,
        us.answer_cnt,
        us.comment_cnt,
        us.badge_cnt,
        us.vote_score,
        us.vote_up,
        us.vote_down,
        ROW_NUMBER() OVER (ORDER BY us.reputation DESC, us.post_cnt DESC) AS rep_rank,
        RANK()      OVER (ORDER BY us.vote_score DESC)                AS vote_rank
    FROM user_stats us
),
tag_usage AS (
    SELECT 
        t.id                                   AS tag_id,
        t.tagname,
        COUNT(pl.id)                           AS linked_cnt,
        COALESCE(LENGTH(p_ex.Body),0)          AS excerpt_len,
        COALESCE(LENGTH(p_wk.Body),0)          AS wiki_len
    FROM tags t
    LEFT JOIN postlinks pl 
        ON pl.relatedpostid = t.id AND pl.linktypeid = 1
    LEFT JOIN posts p_ex 
        ON p_ex.id = t.excerptpostid
    LEFT JOIN posts p_wk 
        ON p_wk.id = t.wikipostid
    GROUP BY t.id, t.tagname, p_ex.body, p_wk.body
),
top_user_tags AS (
    SELECT 
        p.owneruserid,
        t.tagname,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY COUNT(*) DESC) AS rn
    FROM posts p
    CROSS JOIN LATERAL (
        SELECT value AS tag
        FROM UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.tags), '><')) AS value
    ) AS tags(tag)
    JOIN tags t ON t.tagname = tags.tag
    GROUP BY p.owneruserid, t.tagname
    HAVING COUNT(*) > 0
),
main_result AS (
    SELECT
        ur.id,
        ur.displayname,
        ur.reputation,
        ur.post_cnt,
        ur.answer_cnt,
        ur.comment_cnt,
        ur.badge_cnt,
        ur.vote_score,
        ur.rep_rank,
        ur.vote_rank,
        COALESCE(tut.tagname, 'NoTag')                         AS top_tag,
        CASE
            WHEN ur.reputation > 20000 THEN 'Legend'
            WHEN ur.reputation BETWEEN 10000 AND 20000 THEN 'Expert'
            WHEN ur.reputation BETWEEN 5000  AND 9999  THEN 'Seasoned'
            ELSE 'Novice'
        END                                                    AS reputation_tier,
        ('U' || CAST(ur.id AS VARCHAR))                        AS user_code,
        (
            SELECT COUNT(*)
            FROM posts p2
            WHERE p2.owneruserid = ur.id
              AND p2.creationdate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
        )                                                      AS posts_last_year,
        (
            SELECT ph.comment
            FROM posthistory ph
            WHERE ph.postid = (
                    SELECT p3.id
                    FROM posts p3
                    WHERE p3.owneruserid = ur.id
                    ORDER BY p3.creationdate DESC
                    LIMIT 1
                )
              AND ph.posthistorytypeid = 10
            ORDER BY ph.creationdate DESC
            LIMIT 1
        )                                                      AS recent_close_reason
    FROM user_ranks ur
    LEFT JOIN top_user_tags tut
        ON tut.owneruserid = ur.id AND tut.rn = 1
    WHERE ur.rep_rank <= 1000
    ORDER BY ur.rep_rank
    OFFSET 0 ROWS FETCH NEXT 500 ROWS ONLY
)

SELECT * FROM main_result

UNION ALL

SELECT
    NULL AS id,
    NULL AS displayname,
    NULL AS reputation,
    NULL AS post_cnt,
    NULL AS answer_cnt,
    NULL AS comment_cnt,
    NULL AS badge_cnt,
    NULL AS vote_score,
    NULL AS rep_rank,
    NULL AS vote_rank,
    NULL AS top_tag,
    NULL AS reputation_tier,
    NULL AS user_code,
    NULL AS posts_last_year,
    NULL AS recent_close_reason
WHERE NOT EXISTS (SELECT 1 FROM user_ranks);