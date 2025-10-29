-- {"query": "3980.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1851} 

/*  Complex benchmark query using CTEs, window functions, outer joins,
    correlated subqueries, set operators, string handling and NULL logic   */
WITH
/*-------------------------------------------------------------
   Gather per‑user activity metrics
  -------------------------------------------------------------*/
user_stats AS (
    SELECT
        u.id                                   AS user_id,
        u.displayname                          AS user_name,
        COALESCE(u.reputation,0)                AS reputation,
        (SELECT COUNT(*) FROM posts p
           WHERE p.owneruserid = u.id)         AS post_cnt,
        (SELECT COUNT(*) FROM badges b
           WHERE b.userid = u.id)               AS badge_cnt,
        (SELECT COUNT(*) FROM votes v
           WHERE v.userid = u.id)               AS vote_given_cnt
    FROM users u
),
/*-------------------------------------------------------------
   Rank users by reputation / activity
  -------------------------------------------------------------*/
ranked_users AS (
    SELECT
        us.*,
        ROW_NUMBER() OVER (ORDER BY reputation DESC, post_cnt DESC) AS rn
    FROM user_stats us
),
/*-------------------------------------------------------------
   Tag‑level aggregates for tags that appear on many questions
  -------------------------------------------------------------*/
tag_stats AS (
    SELECT
        t.tagname,
        COUNT(p.id)                             AS question_cnt,
        SUM(p.score)                            AS total_score,
        STRING_AGG(DISTINCT SUBSTRING(p.title FROM 1 FOR 60), '; ') AS sample_titles
    FROM tags t
    JOIN posts p
      ON p.posttypeid = 1                                 -- only questions
     AND p.tags LIKE CONCAT('%', t.tagname, '%')          -- crude tag match
    GROUP BY t.tagname
    HAVING COUNT(p.id) > 100
),
/*-------------------------------------------------------------
   Close‑vote / duplicate history per post (correlated later)
  -------------------------------------------------------------*/
post_close_dupe AS (
    SELECT
        ph.postid,
        COUNT(CASE WHEN ph.posthistorytypeid = 10 THEN 1 END) AS close_cnt,
        MAX(CASE WHEN ph.posthistorytypeid = 10 THEN ph.comment END) AS close_reason,
        COUNT(CASE WHEN ph.posthistorytypeid = 35 THEN 1 END) AS dup_cnt,
        MAX(CASE WHEN ph.posthistorytypeid = 35 THEN ph.text END)    AS dup_json
    FROM posthistory ph
    WHERE ph.posthistorytypeid IN (10,35)   -- close or duplicate events
    GROUP BY ph.postid
),
/*-------------------------------------------------------------
   Pull the most‑scored post of each top user (correlated subquery)
  -------------------------------------------------------------*/
user_top_post AS (
    SELECT
        ru.user_id,
        (SELECT p.id
           FROM posts p
          WHERE p.owneruserid = ru.user_id
          ORDER BY p.score DESC NULLS LAST
          LIMIT 1)                         AS top_post_id,
        (SELECT p.tags
           FROM posts p
          WHERE p.owneruserid = ru.user_id
          ORDER BY p.creationdate DESC
          LIMIT 1)                         AS recent_tags
    FROM ranked_users ru
    WHERE ru.rn <= 50
)
SELECT
    ru.user_id,
    ru.user_name,
    ru.reputation,
    ru.post_cnt,
    ru.badge_cnt,
    ru.vote_given_cnt,
    COALESCE(pcd.close_cnt,0)      AS close_votes,
    COALESCE(pcd.dup_cnt,0)        AS duplicate_votes,
    COALESCE(pcd.close_reason,'N/A') AS close_reason,
    ts.tagname,
    ts.question_cnt,
    ts.total_score,
    ts.sample_titles
FROM ranked_users ru
LEFT JOIN user_top_post utp
       ON utp.user_id = ru.user_id
LEFT JOIN post_close_dupe pcd
       ON pcd.postid = utp.top_post_id
LEFT JOIN tag_stats ts
       ON ts.tagname = ANY (STRING_TO_ARRAY(
              REPLACE(REPLACE(utp.recent_tags,'<',''),'>',''), ',' ) )
WHERE ru.rn <= 50

UNION ALL

/*-------------------------------------------------------------
   Aggregate “total” row for quick sanity check
  -------------------------------------------------------------*/
SELECT
    NULL                         AS user_id,
    'ALL_USERS_TOTAL'            AS user_name,
    SUM(reputation)              AS reputation,
    SUM(post_cnt)                AS post_cnt,
    SUM(badge_cnt)               AS badge_cnt,
    SUM(vote_given_cnt)          AS vote_given_cnt,
    SUM(COALESCE(pcd.close_cnt,0))      AS close_votes,
    SUM(COALESCE(pcd.dup_cnt,0))        AS duplicate_votes,
    NULL                         AS close_reason,
    NULL                         AS tagname,
    NULL                         AS question_cnt,
    NULL                         AS total_score,
    NULL                         AS sample_titles
FROM ranked_users ru
LEFT JOIN user_top_post utp
       ON utp.user_id = ru.user_id
LEFT JOIN post_close_dupe pcd
       ON pcd.postid = utp.top_post_id
WHERE ru.rn <= 50
ORDER BY reputation DESC NULLS LAST
LIMIT 100;
