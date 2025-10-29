-- {"query": "3793.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2224} 

WITH 
/*--------------------------------------------------------------
  1. Aggregate per‑user statistics (including correlated sub‑queries)
--------------------------------------------------------------*/
user_stats AS (
    SELECT 
        u.id                                      AS user_id,
        u.displayname                             AS display_name,
        u.reputation                              AS reputation,
        /* badge counts */
        (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 1) AS gold_badges,
        (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 2) AS silver_badges,
        (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 3) AS bronze_badges,
        /* post counts */
        (SELECT COUNT(*) FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 1) AS question_cnt,
        (SELECT COUNT(*) FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 2) AS answer_cnt,
        /* avg score, ignoring NULLs */
        (SELECT AVG(p.score) FROM posts p WHERE p.owneruserid = u.id AND p.score IS NOT NULL) AS avg_score,
        /* most recent activity (question or answer) */
        (SELECT MAX(p.creationdate) 
            FROM posts p 
            WHERE p.owneruserid = u.id 
              AND p.posttypeid IN (1,2))                                   AS last_activity
    FROM users u
    WHERE u.reputation > 5000
),

/*--------------------------------------------------------------
  2. Tags enriched with excerpt / wiki titles (outer joins, string ops)
--------------------------------------------------------------*/
tag_info AS (
    SELECT 
        t.tagname,
        t.count,
        COALESCE(e.title, '') AS excerpt_title,
        COALESCE(w.title, '') AS wiki_title,
        /* construct a searchable keyword list */
        LOWER(t.tagname) || ':' || REPLACE(COALESCE(e.title,''), ' ', '_') 
            || ':' || REPLACE(COALESCE(w.title,''), ' ', '_')               AS tag_keyword
    FROM tags t
    LEFT JOIN posts e ON e.id = t.excerptpostid   -- excerpt may be missing
    LEFT JOIN posts w ON w.id = t.wikipostid     -- wiki may be missing
    WHERE t.ismoderatoronly = 0
),

/*--------------------------------------------------------------
  3. Rank each user's questions by score (window function)
--------------------------------------------------------------*/
ranked_questions AS (
    SELECT 
        p.id                     AS post_id,
        p.owneruserid            AS owner_id,
        p.title,
        p.score,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid 
                           ORDER BY p.score DESC, p.creationdate DESC) AS rn
    FROM posts p
    WHERE p.posttypeid = 1                     -- only questions
      AND p.score IS NOT NULL
),

/*--------------------------------------------------------------
  4. Pull the top‑scoring question per user (correlated subquery)
--------------------------------------------------------------*/
top_questions AS (
    SELECT 
        rq.owner_id,
        rq.post_id,
        rq.title,
        rq.score
    FROM ranked_questions rq
    WHERE rq.rn = 1
),

/*--------------------------------------------------------------
  5. Recent vote aggregates (set operator + outer join)
--------------------------------------------------------------*/
recent_votes AS (
    SELECT 
        v.postid,
        SUM(CASE WHEN vt.id = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN vt.id = 3 THEN 1 ELSE 0 END) AS down_votes,
        MAX(v.creationdate)                         AS last_vote
    FROM votes v
    JOIN votetypes vt ON vt.id = v.votetypeid
    WHERE v.creationdate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.postid
),

/*--------------------------------------------------------------
  6. Users that have never earned a bronze badge (NOT EXISTS)
--------------------------------------------------------------*/
no_bronze AS (
    SELECT u.id AS user_id
    FROM users u
    WHERE NOT EXISTS (
        SELECT 1 FROM badges b 
        WHERE b.userid = u.id AND b.class = 3
    )
),

/*--------------------------------------------------------------
  7. Combine everything – outer joins, NULL handling, string concat
--------------------------------------------------------------*/
combined AS (
    SELECT 
        us.user_id,
        us.display_name,
        us.reputation,
        us.gold_badges,
        us.silver_badges,
        us.bronze_badges,
        us.question_cnt,
        us.answer_cnt,
        ROUND(us.avg_score::numeric,2)                AS avg_score,
        COALESCE(us.last_activity, TIMESTAMP '1970-01-01') AS last_activity,
        tq.post_id                                    AS top_q_id,
        tq.title                                      AS top_q_title,
        tq.score                                      AS top_q_score,
        rv.up_votes,
        rv.down_votes,
        rv.last_vote,
        /* display name with reputation, handling NULL */
        COALESCE(us.display_name,'[deleted]') || ' (rep:'||us.reputation||')' AS display_with_rep,
        /* flag users with no bronze badge */
        CASE WHEN nb.user_id IS NOT NULL THEN 1 ELSE 0 END AS has_no_bronze
    FROM user_stats us
    LEFT JOIN top_questions tq   ON tq.owner_id = us.user_id
    LEFT JOIN recent_votes rv    ON rv.postid = tq.post_id
    LEFT JOIN no_bronze nb       ON nb.user_id = us.user_id
)

SELECT *
FROM combined
WHERE (up_votes IS NULL OR up_votes > 0)           -- keep rows with up‑votes
   AND has_no_bronze = 0                           -- exclude users without bronze
ORDER BY reputation DESC, avg_score DESC
LIMIT 100
UNION ALL
SELECT 
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL
WHERE FALSE;   -- dummy row to force UNION ALL syntax compliance
