-- {"query": "3008.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2703} 

WITH
-- 1. Basic per‑user statistics
user_stats AS (
    SELECT
        u.id                                     AS user_id,
        u.displayname,
        u.reputation,
        COALESCE(SUM(CASE v.votetypeid
                       WHEN 2 THEN 1          -- upvote
                       WHEN 3 THEN -1         -- downvote
                       ELSE 0 END),0)        AS net_vote_score,
        COUNT(DISTINCT b.id)                     AS badge_cnt,
        ROW_NUMBER() OVER (ORDER BY u.reputation DESC) AS rep_rank
    FROM users u
    LEFT JOIN votes v   ON v.userid = u.id
    LEFT JOIN badges b  ON b.userid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),

-- 2. Tag popularity ranking
top_tags AS (
    SELECT
        t.tagname,
        t.count,
        ROW_NUMBER() OVER (ORDER BY t.count DESC) AS tag_rank
    FROM tags t
    WHERE t.ismoderatoronly = 0
),

-- 3. Question‑level aggregates, using window functions
question_stats AS (
    SELECT
        p.id                                   AS q_id,
        p.title,
        p.creationdate,
        p.score                                AS q_score,
        p.viewcount,
        p.favoritecount,
        COALESCE(p.tags,'')                    AS raw_tags,
        array_length(string_to_array(substring(p.tags,2,length(p.tags)-2),'><'),1)
                                               AS tag_cnt,
        SUM(CASE WHEN v.votetypeid = 2 THEN 1
                 WHEN v.votetypeid = 3 THEN -1
                 ELSE 0 END) OVER (PARTITION BY p.id) AS net_votes,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid
                           ORDER BY p.score DESC)          AS owner_q_rank
    FROM posts p
    LEFT JOIN votes v ON v.postid = p.id
    WHERE p.posttypeid = 1        -- only questions
),

-- 4. Per‑user activity per tag, with correlated subqueries
user_tag_activity AS (
    SELECT
        u.id                                   AS user_id,
        t.tagname,
        COUNT(*) FILTER (WHERE p.posttypeid = 1) AS questions_asked,
        COUNT(*) FILTER (WHERE a.id IS NOT NULL) AS answers_given,
        (SELECT COALESCE(SUM(CASE WHEN v2.votetypeid = 2 THEN 1
                                 WHEN v2.votetypeid = 3 THEN -1
                                 ELSE 0 END),0)
         FROM votes v2
         JOIN posts p2 ON p2.id = v2.postid
         WHERE p2.owneruserid = u.id)          AS total_votes_received
    FROM users u
    LEFT JOIN posts p ON p.owneruserid = u.id AND p.posttypeid = 1
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.tags,2,length(p.tags)-2),'><'))
               AS tagname
    ) t ON TRUE
    LEFT JOIN posts a ON a.owneruserid = u.id AND a.posttypeid = 2
    GROUP BY u.id, t.tagname
),

-- 5. Recent duplicate‑close events extracted from PostHistory
recent_duplicates AS (
    SELECT
        p.id                                   AS q_id,
        p.title,
        p.creationdate,
        ph.comment::int                        AS duplicate_of_qid,
        d.title                                AS duplicate_of_title,
        EXTRACT(DAY FROM (ph.creationdate - p.creationdate))::int AS days_to_close
    FROM posts p
    JOIN posthistory ph
          ON ph.postid = p.id
         AND ph.posthistorytypeid = 10                -- Post Closed
         AND ph.comment ~ '^\d+$'                     -- comment holds duplicate id
    LEFT JOIN posts d ON d.id = ph.comment::int
    WHERE p.posttypeid = 1
      AND p.closeddate IS NOT NULL
),

-- 6. Combine everything for a heavy‑weight benchmark query
combined AS (
    SELECT
        us.user_id,
        us.displayname,
        us.reputation,
        us.net_vote_score,
        us.badge_cnt,
        us.rep_rank,
        uta.tagname,
        tt.tag_rank,
        qs.q_id,
        qs.title,
        qs.q_score,
        qs.net_votes,
        qs.viewcount,
        qs.favoritecount,
        qs.tag_cnt,
        rd.duplicate_of_qid,
        rd.duplicate_of_title,
        rd.days_to_close
    FROM user_stats us
    LEFT JOIN user_tag_activity uta   ON uta.user_id = us.user_id
    LEFT JOIN top_tags tt             ON tt.tagname = uta.tagname
    LEFT JOIN question_stats qs       ON qs.owner_q_rank = 1
                                      AND qs.q_id = (
                                          SELECT q2.id
                                          FROM posts q2
                                          WHERE q2.owneruserid = us.user_id
                                            AND q2.posttypeid = 1
                                          ORDER BY q2.score DESC
                                          LIMIT 1)
    LEFT JOIN recent_duplicates rd   ON rd.q_id = qs.q_id
    WHERE (us.reputation > 20000 OR us.badge_cnt >= 10)
),

-- 7. A dummy set to force a set‑operator path
dummy AS (
    SELECT NULL::int AS user_id,
           NULL::varchar AS displayname,
           NULL::int AS reputation,
           NULL::int AS net_vote_score,
           NULL::int AS badge_cnt,
           NULL::int AS rep_rank,
           NULL::varchar AS tagname,
           NULL::int AS tag_rank,
           NULL::int AS q_id,
           NULL::varchar AS title,
           NULL::int AS q_score,
           NULL::int AS net_votes,
           NULL::int AS viewcount,
           NULL::int AS favoritecount,
           NULL::int AS tag_cnt,
           NULL::int AS duplicate_of_qid,
           NULL::varchar AS duplicate_of_title,
           NULL::int AS days_to_close
)

-- Final result: UNION ALL with INTERSECT to increase planner work
SELECT *
FROM combined
WHERE rep_rank <= 200
ORDER BY rep_rank
LIMIT 150
UNION ALL
SELECT *
FROM dummy
INTERSECT
SELECT *
FROM combined
WHERE badge_cnt >= 5;
