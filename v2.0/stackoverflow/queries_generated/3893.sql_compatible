WITH
    tag_filtered_questions AS (
        SELECT
            p.id          AS question_id,
            p.title,
            p.tags
        FROM   posts p
        WHERE  p.posttypeid = 1
          AND  p.tags IS NOT NULL
          AND  EXISTS (
                SELECT 1
                FROM   unnest(
                           string_to_array(
                               substr(p.tags, 2, length(p.tags) - 2),
                               '><'
                           )
                       ) AS t(tag)
                WHERE  lower(t.tag) = 'sql'
          )
    ),

    answers_with_votes AS (
        SELECT
            a.id                         AS answer_id,
            a.parentid                   AS question_id,
            a.owneruserid                AS owner_user_id,
            a.creationdate,
            a.score,
            COALESCE(v.up_votes,   0)    AS up_vote_count,
            COALESCE(v.down_votes, 0)    AS down_vote_count
        FROM   posts a
        LEFT JOIN (
            SELECT
                vote.postid,
                SUM(CASE WHEN vote.votetypeid = 2 THEN 1 ELSE 0 END) AS up_votes,
                SUM(CASE WHEN vote.votetypeid = 3 THEN 1 ELSE 0 END) AS down_votes
            FROM   votes vote
            GROUP BY vote.postid
        ) v ON v.postid = a.id
        WHERE  a.posttypeid = 2
    ),

    user_activity AS (
        SELECT
            u.id                                     AS user_id,
            u.displayname,
            u.reputation,
            MAX(p.creationdate)                     AS last_post_date,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS question_count,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS answer_count,
            COUNT(b.id)                             AS badge_count,
            SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_badge_count
        FROM   users u
        LEFT JOIN posts   p ON p.owneruserid = u.id
        LEFT JOIN badges  b ON b.userid = u.id
        GROUP BY u.id, u.displayname, u.reputation
    ),

    top_answerers AS (
        SELECT
            ua.user_id,
            ua.displayname,
            ua.reputation,
            ua.gold_badge_count,
            AVG(a.score) OVER (PARTITION BY ua.user_id)           AS avg_answer_score,
            ROW_NUMBER() OVER (ORDER BY ua.reputation DESC,
                                         ua.gold_badge_count DESC) AS reputation_rank
        FROM   user_activity ua
        JOIN   answers_with_votes a ON a.owner_user_id = ua.user_id
        JOIN   tag_filtered_questions tq ON tq.question_id = a.question_id
        WHERE  ua.reputation > 1000
    ),

    users_without_answers AS (
        SELECT
            ua.user_id,
            ua.displayname,
            ua.reputation,
            0                                             AS gold_badge_count,
            CAST(NULL AS numeric)                         AS avg_answer_score,
            CAST(NULL AS integer)                         AS reputation_rank
        FROM   user_activity ua
        LEFT JOIN answers_with_votes a ON a.owner_user_id = ua.user_id
        WHERE  a.answer_id IS NULL
          AND  ua.reputation > 1000
    )

SELECT *
FROM (
        SELECT
            user_id,
            displayname,
            reputation,
            gold_badge_count,
            ROUND(avg_answer_score, 2) AS avg_answer_score,
            reputation_rank
        FROM   top_answerers
        WHERE  reputation_rank <= 50

        UNION ALL

        SELECT
            user_id,
            displayname,
            reputation,
            gold_badge_count,
            COALESCE(avg_answer_score, 0) AS avg_answer_score,
            reputation_rank
        FROM   users_without_answers
     ) AS combined
ORDER BY reputation DESC,
         avg_answer_score DESC
LIMIT 100;