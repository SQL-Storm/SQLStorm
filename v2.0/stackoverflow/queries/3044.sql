WITH
    user_stats AS (
        SELECT
            u.id                                    AS user_id,
            u.displayname,
            u.reputation,
            COALESCE(u.location, 'Unknown')          AS location,
            COUNT(b.id) FILTER (WHERE b.class = 1)   AS gold_badges,
            COUNT(b.id) FILTER (WHERE b.class = 2)   AS silver_badges,
            COUNT(b.id) FILTER (WHERE b.class = 3)   AS bronze_badges
        FROM users u
        LEFT JOIN badges b ON b.userid = u.id
        GROUP BY u.id, u.displayname, u.reputation, u.location
    ),

    recent_questions AS (
        SELECT
            p.owneruserid                         AS user_id,
            p.id                                   AS post_id,
            p.creationdate,
            p.title,
            p.tags,
            p.score,
            p.viewcount,
            p.answercount,
            ROW_NUMBER() OVER (
                PARTITION BY p.owneruserid
                ORDER BY p.creationdate DESC
            )                                      AS rn
        FROM posts p
        WHERE p.posttypeid = 1
          AND p.creationdate > (DATE '2024-10-01' - INTERVAL '180 days')
    ),

    answer_stats AS (
        SELECT
            a.parentid                              AS question_id,
            COUNT(*)                                AS total_answers,
            SUM(CASE WHEN a.id = q.acceptedanswerid THEN 1 ELSE 0 END) AS accepted_answers
        FROM posts a
        JOIN posts q ON q.id = a.parentid AND q.posttypeid = 1
        WHERE a.posttypeid = 2
        GROUP BY a.parentid
    ),

    vote_agg AS (
        SELECT
            v.postid,
            SUM(CASE
                    WHEN v.votetypeid = 2 THEN 1
                    WHEN v.votetypeid = 3 THEN -1
                    ELSE 0
                END)                                 AS net_votes
        FROM votes v
        GROUP BY v.postid
    ),

    latest_edit AS (
        SELECT
            ph.postid,
            MAX(ph.creationdate) AS last_edit
        FROM posthistory ph
        WHERE ph.posthistorytypeid IN (4,5,6)
        GROUP BY ph.postid
    )

SELECT
    us.user_id,
    us.displayname,
    us.reputation,
    us.location,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    rq.post_id,
    rq.title,
    rq.creationdate          AS post_date,
    rq.score                 AS original_score,
    COALESCE(va.net_votes,0) AS net_vote_score,
    rq.viewcount,
    rq.answercount,
    COALESCE(answer_stats.total_answers,0)   AS total_answers,
    COALESCE(answer_stats.accepted_answers,0) AS accepted_answers,
    LEAST(rq.rn,5)                AS recent_rank,
    CASE
        WHEN rq.answercount IS NULL OR rq.answercount = 0 THEN NULL
        ELSE (rq.score * COALESCE(rq.viewcount,0)) / NULLIF(rq.answercount,0)
    END                           AS engagement_score,
    le.last_edit
FROM user_stats us
LEFT JOIN recent_questions rq
       ON rq.user_id = us.user_id
      AND rq.rn <= 5
LEFT JOIN vote_agg va
       ON va.postid = rq.post_id
LEFT JOIN answer_stats
       ON answer_stats.question_id = rq.post_id
LEFT JOIN latest_edit le
       ON le.postid = rq.post_id
WHERE (us.reputation > 5000 OR us.gold_badges > 0)
  AND (rq.tags IS NOT NULL AND rq.tags <> '')
UNION ALL
SELECT
    us.user_id,
    us.displayname,
    us.reputation,
    us.location,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    NULL AS post_id,
    NULL AS title,
    NULL AS post_date,
    NULL AS original_score,
    NULL AS net_vote_score,
    NULL AS viewcount,
    NULL AS answercount,
    NULL AS total_answers,
    NULL AS accepted_answers,
    NULL AS recent_rank,
    NULL AS engagement_score,
    NULL AS last_edit
FROM user_stats us
WHERE NOT EXISTS (
    SELECT 1 FROM recent_questions rq WHERE rq.user_id = us.user_id
)
ORDER BY reputation DESC, gold_badges DESC, user_id
LIMIT 100;