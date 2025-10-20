-- {"query": "25046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2509} 

/*  Benchmark query – combines CTEs, window functions, outer joins, 
    correlated subqueries, set operators, string manipulation and NULL logic */
WITH
/* ------------------------------------------------------------------
   1. Aggregate user statistics, including badge counts per class
   ------------------------------------------------------------------ */
user_stats AS (
    SELECT
        u.id                                     AS user_id,
        u.displayname                            AS user_name,
        u.reputation,
        COUNT(b.id)               FILTER (WHERE b.class = 1) AS gold_badges,
        COUNT(b.id)               FILTER (WHERE b.class = 2) AS silver_badges,
        COUNT(b.id)               FILTER (WHERE b.class = 3) AS bronze_badges,
        COALESCE(SUM(p.score), 0)                 AS total_post_score,
        AVG(p.score)              FILTER (WHERE p.posttypeid = 2) AS avg_answer_score,
        MAX(p.creationdate)                     AS last_post_date
    FROM users u
    LEFT JOIN badges b      ON b.userid = u.id
    LEFT JOIN posts  p      ON p.owneruserid = u.id
    WHERE u.reputation > 1000
    GROUP BY u.id, u.displayname, u.reputation
),

/* ------------------------------------------------------------------
   2. Most recent voting activity per user
   ------------------------------------------------------------------ */
recent_votes AS (
    SELECT
        v.userid,
        MAX(v.creationdate)                                      AS last_vote_date,
        COUNT(*) FILTER (WHERE vt.name = 'UpMod')               AS up_votes_given,
        COUNT(*) FILTER (WHERE vt.name = 'DownMod')             AS down_votes_given
    FROM votes v
    JOIN votetypes vt ON vt.id = v.votetypeid
    GROUP BY v.userid
),

/* ------------------------------------------------------------------
   3. Latest post per tag (tags are stored as '<tag1><tag2>' in Posts.Tags)
   ------------------------------------------------------------------ */
tag_latest_posts AS (
    SELECT
        t.tagname,
        t.count                                   AS tag_use_count,
        p.id                                       AS latest_post_id,
        p.title                                    AS latest_post_title,
        p.creationdate                             AS latest_post_date,
        ROW_NUMBER() OVER (PARTITION BY t.tagname
                           ORDER BY p.creationdate DESC) AS rn
    FROM tags t
    LEFT JOIN LATERAL (
        SELECT *
        FROM posts p
        WHERE p.tags IS NOT NULL
          AND p.tags LIKE CONCAT('%<', t.tagname, '>%')
        ORDER BY p.creationdate DESC
        LIMIT 1
    ) p ON TRUE
    WHERE t.ismoderatoronly = 0
),

top_tags AS (
    SELECT
        tagname,
        tag_use_count,
        latest_post_id,
        latest_post_title,
        latest_post_date
    FROM tag_latest_posts
    WHERE rn = 1
    ORDER BY tag_use_count DESC
    LIMIT 10
),

/* ------------------------------------------------------------------
   4. Most recent question per user (question = PostTypeId 1)
   ------------------------------------------------------------------ */
user_recent_questions AS (
    SELECT
        u.id                                    AS user_id,
        p.id                                    AS post_id,
        p.title                                 AS title,
        p.creationdate                          AS creationdate,
        ROW_NUMBER() OVER (PARTITION BY u.id
                           ORDER BY p.creationdate DESC) AS rn
    FROM users u
    JOIN posts p ON p.owneruserid = u.id
    WHERE p.posttypeid = 1
),

/* ------------------------------------------------------------------
   5. Correlated sub‑query: number of distinct tags a user has ever used
   ------------------------------------------------------------------ */
user_tag_counts AS (
    SELECT
        u.id                                    AS user_id,
        (SELECT COUNT(DISTINCT trim(both '<>' FROM unnest(string_to_array(p.tags, '><'))))
         FROM posts p
         WHERE p.owneruserid = u.id
           AND p.tags IS NOT NULL)             AS distinct_tag_count
    FROM users u
),

/* ------------------------------------------------------------------
   6. Users that satisfy the final filter – join all pieces together
   ------------------------------------------------------------------ */
final_users AS (
    SELECT
        us.user_id,
        us.user_name,
        us.reputation,
        us.gold_badges,
        us.silver_badges,
        us.bronze_badges,
        us.total_post_score,
        us.avg_answer_score,
        us.last_post_date,
        rv.last_vote_date,
        rv.up_votes_given,
        rv.down_votes_given,
        urq.title          AS recent_question_title,
        urq.creationdate   AS recent_question_date,
        utc.distinct_tag_count,
        tt.tagname,
        tt.tag_use_count,
        tt.latest_post_title AS tag_latest_post_title,
        tt.latest_post_date  AS tag_latest_post_date
    FROM user_stats us
    LEFT JOIN recent_votes rv          ON rv.userid = us.user_id
    LEFT JOIN user_recent_questions urq
          ON urq.user_id = us.user_id AND urq.rn = 1
    LEFT JOIN user_tag_counts utc      ON utc.user_id = us.user_id
    LEFT JOIN top_tags tt              ON TRUE               -- cross join to expose top‑tags
    WHERE (us.gold_badges > 0 OR us.silver_badges > 0)
      AND (us.reputation + COALESCE(rv.up_votes_given,0)
           - COALESCE(rv.down_votes_given,0)) > 1500
)

/* ------------------------------------------------------------------
   7. Final result set – include a dummy row via UNION ALL to test
       set‑operator handling when the main query returns no rows.
   ------------------------------------------------------------------ */
SELECT *
FROM final_users
ORDER BY reputation DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY

UNION ALL

SELECT
    NULL::int      AS user_id,
    NULL::varchar  AS user_name,
    NULL::int      AS reputation,
    NULL::int      AS gold_badges,
    NULL::int      AS silver_badges,
    NULL::int      AS bronze_badges,
    NULL::bigint   AS total_post_score,
    NULL::numeric  AS avg_answer_score,
    NULL::timestamp AS last_post_date,
    NULL::timestamp AS last_vote_date,
    NULL::int      AS up_votes_given,
    NULL::int      AS down_votes_given,
    NULL::varchar  AS recent_question_title,
    NULL::timestamp AS recent_question_date,
    NULL::int      AS distinct_tag_count,
    NULL::varchar  AS tagname,
    NULL::int      AS tag_use_count,
    NULL::varchar  AS tag_latest_post_title,
    NULL::timestamp AS tag_latest_post_date
WHERE NOT EXISTS (SELECT 1 FROM final_users);
