WITH recent_questions AS (
    SELECT Id,
           Score,
           ViewCount,
           AnswerCount,
           Tags,
           CreationDate
    FROM Posts
    WHERE PostTypeId = 1
      AND ClosedDate IS NULL
      AND CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),

tagged AS (
    SELECT Id                         AS question_id,
           Score                      AS question_score,
           ViewCount                  AS question_view,
           AnswerCount                AS question_answer,
           CreationDate               AS question_date,
           UNNEST(
               STRING_TO_ARRAY(
                   REGEXP_REPLACE(Tags, '^<|>$', '', 'g'),
                   '><'
               )
           ) AS tag
    FROM recent_questions
),

vote_counts AS (
    SELECT PostId,
           COUNT(*) AS vote_cnt
    FROM Votes
    WHERE VoteTypeId IN (2,3)
    GROUP BY PostId
)

SELECT t.tag,
       COUNT(*)                                         AS question_count,
       ROUND(AVG(t.question_score), 2)                  AS avg_score,
       ROUND(AVG(t.question_view), 2)                   AS avg_views,
       ROUND(AVG(t.question_answer), 2)                 AS avg_answers,
       ROUND(AVG(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - t.question_date))/86400), 2) 
        AS avg_age_days,
       COALESCE(SUM(v.vote_cnt), 0)                    AS total_votes
FROM tagged t
LEFT JOIN vote_counts v
       ON t.question_id = v.PostId
GROUP BY t.tag
ORDER BY avg_score DESC, question_count DESC
LIMIT 30;