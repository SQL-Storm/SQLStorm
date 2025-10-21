WITH question_answers AS (
    SELECT
        q.Id            AS question_id,
        q.CreationDate  AS q_created,
        q.Score         AS q_score,
        q.ViewCount     AS q_views,
        q.OwnerUserId   AS q_owner,
        a.Id            AS answer_id,
        a.CreationDate  AS a_created,
        a.Score         AS a_score
    FROM Posts q
    JOIN Posts a
      ON a.ParentId = q.Id
     AND a.PostTypeId = 2
   WHERE q.PostTypeId = 1
),
tagged AS (
    SELECT
        qa.*,
        UNNEST(
          STRING_TO_ARRAY(
            SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2),
            '><'
          )
        ) AS tag
    FROM question_answers qa
    JOIN Posts p
      ON p.Id = qa.question_id
),
tag_metrics AS (
    SELECT
        tag,
        COUNT(DISTINCT question_id)   AS total_questions,
        COUNT(answer_id)              AS total_answers,
        AVG(EXTRACT(EPOCH FROM (a_created - q_created)) / 3600.0) AS avg_answer_time,
        AVG(q_score)                  AS avg_question_score,
        AVG(a_score)                  AS avg_answer_score,
        SUM(q_views)                  AS total_question_views
    FROM tagged
    GROUP BY tag
),
badge_counts AS (
    SELECT
        LOWER(t.TagName) AS tag,
        COUNT(b.Id)      AS badge_earners
    FROM Tags t
    JOIN Badges b
      ON CAST(b.TagBased AS BOOLEAN) = TRUE
     AND LOWER(b.Name) = LOWER(t.TagName)
    GROUP BY LOWER(t.TagName)
),
comment_counts AS (
    SELECT
        tg.tag,
        COUNT(c.Id) AS total_comments
    FROM tagged tg
    JOIN Comments c
      ON c.PostId = tg.answer_id
    GROUP BY tg.tag
)
SELECT
    tm.tag,
    tm.total_questions,
    tm.total_answers,
    tm.avg_answer_time,
    tm.avg_question_score,
    tm.avg_answer_score,
    tm.total_question_views,
    COALESCE(bc.badge_earners, 0) AS badge_earners,
    COALESCE(cc.total_comments, 0) AS total_comments,
    RANK() OVER (
      ORDER BY tm.total_questions DESC,
               tm.avg_answer_time ASC
    ) AS activity_rank
FROM tag_metrics tm
LEFT JOIN badge_counts bc
  ON bc.tag = tm.tag
LEFT JOIN comment_counts cc
  ON cc.tag = tm.tag
WHERE tm.total_questions > 500
ORDER BY activity_rank,
         tm.total_question_views DESC;