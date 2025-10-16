WITH
user_stats AS (
    SELECT
        u.id                                     AS user_id,
        u.displayname,
        u.reputation,
        COALESCE(u.location, '[no location]')    AS location,
        COUNT(b.id) FILTER (WHERE b.class = 1)   AS gold_badges,
        COUNT(b.id) FILTER (WHERE b.class = 2)   AS silver_badges,
        COUNT(b.id) FILTER (WHERE b.class = 3)   AS bronze_badges,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS questions_asked,
        COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answers_given,
        AVG(CASE WHEN p.posttypeid = 2 THEN p.score END) AS avg_answer_score,
        SUM(CASE WHEN ph.posthistorytypeid = 10 THEN 1 ELSE 0 END) AS times_closed
    FROM users u
    LEFT JOIN badges   b  ON b.userid   = u.id
    LEFT JOIN posts    p  ON p.owneruserid = u.id
    LEFT JOIN posthistory ph
           ON ph.postid = p.id
          AND ph.posthistorytypeid = 10
    GROUP BY u.id, u.displayname, u.reputation, u.location
),
recent_votes AS (
    SELECT
        v.userid               AS user_id,
        COUNT(*)               AS votes_last_30d,
        MAX(v.creationdate)    AS last_vote_date
    FROM votes v
    WHERE v.creationdate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
    GROUP BY v.userid
),
top_answer_per_user AS (
    SELECT
        a.owneruserid                        AS user_id,
        a.id                                 AS answer_id,
        a.score                              AS answer_score,
        q.id                                 AS question_id,
        q.title                              AS question_title,
        ROW_NUMBER() OVER (PARTITION BY a.owneruserid
                           ORDER BY a.score DESC,
                                    a.creationdate ASC) AS rn
    FROM posts a
    JOIN posts q ON q.id = a.parentid
    WHERE a.posttypeid = 2
),
user_question_tags AS (
    SELECT
        p.owneruserid               AS user_id,
        STRING_AGG(t.tag, ',' ORDER BY t.tag) AS tag_csv
    FROM posts p
    CROSS JOIN LATERAL (
        SELECT TRIM(BOTH '><' FROM val) AS tag
        FROM UNNEST(string_to_array(p.tags, '><')) AS val
    ) t
    WHERE p.posttypeid = 1
      AND p.tags IS NOT NULL
    GROUP BY p.owneruserid
),
qualified_users AS (
    SELECT
        us.user_id,
        us.displayname,
        us.reputation,
        us.location,
        us.gold_badges,
        us.silver_badges,
        us.bronze_badges,
        us.questions_asked,
        us.answers_given,
        ROUND(CAST(us.avg_answer_score AS numeric), 2) AS avg_answer_score,
        us.times_closed,
        COALESCE(rv.votes_last_30d, 0)         AS votes_last_30d,
        COALESCE(rv.last_vote_date,
                 CAST('1970-01-01 00:00:00' AS timestamp)) AS last_vote_date,
        tq.answer_id,
        tq.answer_score,
        tq.question_title,
        COALESCE(ut.tag_csv, '')               AS question_tags
    FROM user_stats us
    LEFT JOIN recent_votes rv        ON rv.user_id = us.user_id
    LEFT JOIN top_answer_per_user tq ON tq.user_id = us.user_id AND tq.rn = 1
    LEFT JOIN user_question_tags ut  ON ut.user_id = us.user_id
    WHERE us.reputation > 10000
      AND (us.gold_badges + us.silver_badges + us.bronze_badges) >= 10
      AND tq.answer_id IS NOT NULL
)
SELECT *
FROM (
    SELECT *
    FROM qualified_users
    UNION ALL
    SELECT
        CAST(NULL AS integer)        AS user_id,
        CAST(NULL AS varchar)        AS displayname,
        CAST(NULL AS integer)        AS reputation,
        CAST(NULL AS varchar)        AS location,
        CAST(NULL AS integer)        AS gold_badges,
        CAST(NULL AS integer)        AS silver_badges,
        CAST(NULL AS integer)        AS bronze_badges,
        CAST(NULL AS integer)        AS questions_asked,
        CAST(NULL AS integer)        AS answers_given,
        CAST(NULL AS numeric)        AS avg_answer_score,
        CAST(NULL AS integer)        AS times_closed,
        CAST(NULL AS integer)        AS votes_last_30d,
        CAST(NULL AS timestamp)      AS last_vote_date,
        CAST(NULL AS integer)        AS answer_id,
        CAST(NULL AS integer)        AS answer_score,
        CAST(NULL AS varchar)        AS question_title,
        CAST(NULL AS varchar)        AS question_tags
) t
ORDER BY reputation DESC NULLS LAST
LIMIT 100;