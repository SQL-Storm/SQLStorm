-- {"query": "3813.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2961} 

WITH tag_cte AS (
    SELECT t.id,
           LOWER(t.tagname) AS tagname
    FROM   tags t
    WHERE  t.ismoderatoronly = 0
),

user_stats AS (
    SELECT u.id                                    AS user_id,
           u.displayname,
           u.reputation,
           COUNT(p.id) FILTER (WHERE p.posttypeid = 2)                               AS answer_cnt,
           SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END)                         AS up_votes,
           SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END)                         AS down_votes,
           COUNT(b.id) FILTER (WHERE b.class = 1)                                    AS gold_badge_cnt,
           STRING_AGG(DISTINCT t.tagname, ',') FILTER (WHERE t.tagname IS NOT NULL) AS tags_answered
    FROM   users u
    LEFT   JOIN posts   p  ON p.owneruserid = u.id AND p.posttypeid = 2
    LEFT   JOIN votes   v  ON v.postid = p.id AND v.votetypeid IN (2,3)
    LEFT   JOIN LATERAL (
               SELECT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.tags, '><'))) AS tag_raw
           ) AS tags_raw ON TRUE
    LEFT   JOIN tag_cte t ON LOWER(tags_raw.tag_raw) = t.tagname
    LEFT   JOIN badges  b ON b.userid = u.id
    GROUP  BY u.id, u.displayname, u.reputation
),

badge_check AS (
    SELECT us.user_id,
           CASE WHEN EXISTS (
                    SELECT 1
                    FROM   badges b
                    WHERE  b.userid = us.user_id
                       AND b.class = 1
                       AND b.tagbased = 1
                       AND LOWER(b.name) IN (SELECT tagname FROM tag_cte)
                )
                THEN 1 ELSE 0 END AS has_gold_tag_badge
    FROM   user_stats us
),

ranked AS (
    SELECT us.*,
           bc.has_gold_tag_badge,
           COALESCE(us.up_votes,0)::DECIMAL /
               NULLIF(COALESCE(us.down_votes,0),0)                                 AS up_down_ratio,
           RANK()     OVER (ORDER BY us.reputation DESC, us.answer_cnt DESC)      AS rep_rank,
           ROW_NUMBER() OVER (PARTITION BY bc.has_gold_tag_badge
                              ORDER BY us.answer_cnt DESC)                      AS rn_by_badge
    FROM   user_stats   us
    LEFT   JOIN badge_check bc ON bc.user_id = us.user_id
)

SELECT r.user_id,
       r.displayname,
       r.reputation,
       r.answer_cnt,
       r.up_votes,
       r.down_votes,
       r.up_down_ratio,
       r.gold_badge_cnt,
       r.tags_answered,
       r.has_gold_tag_badge,
       r.rep_rank,
       r.rn_by_badge
FROM   ranked r
WHERE  r.answer_cnt > 0

UNION ALL

SELECT u.id,
       u.displayname,
       u.reputation,
       0                                    AS answer_cnt,
       0                                    AS up_votes,
       0                                    AS down_votes,
       NULL                                 AS up_down_ratio,
       (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 1) AS gold_badge_cnt,
       NULL                                 AS tags_answered,
       CASE WHEN EXISTS (SELECT 1 FROM badges b
                         WHERE b.userid = u.id
                           AND b.class = 1
                           AND b.tagbased = 1) THEN 1 ELSE 0 END          AS has_gold_tag_badge,
       RANK()     OVER (ORDER BY u.reputation DESC)                               AS rep_rank,
       ROW_NUMBER() OVER (PARTITION BY
                              CASE WHEN EXISTS (SELECT 1 FROM badges b
                                                WHERE b.userid = u.id
                                                  AND b.class = 1
                                                  AND b.tagbased = 1)
                                   THEN 1 ELSE 0 END
                          ORDER BY u.reputation DESC)                             AS rn_by_badge
FROM   users u
WHERE  NOT EXISTS (SELECT 1 FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 2)

ORDER BY rep_rank, user_id
LIMIT 200;
