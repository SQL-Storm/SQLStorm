WITH
DateRanges AS (
    SELECT CAST(date_trunc('month', MIN(CreationDate)) AS date) AS month_start
      FROM Posts
),
Months AS (
    -- generate 12 months starting from the min month_start
    SELECT CAST(month_start + (n * INTERVAL '1 month') AS date) AS month_start
      FROM DateRanges,
           (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11)) AS v(n)
),
Questions AS (
    SELECT
        p.Id        AS question_id,
        p.CreationDate,
        -- split tags like "<tag1><tag2>" into rows of tag text
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
      FROM Posts p
     WHERE p.PostTypeId = 1
),
Answers AS (
    SELECT
        a.ParentId   AS question_id,
        a.Id         AS answer_id,
        a.CreationDate,
        a.Score      AS answer_score,
        u.Reputation AS answerer_reputation,
        a.OwnerUserId
      FROM Posts a
      JOIN Users u ON u.Id = a.OwnerUserId
     WHERE a.PostTypeId = 2
),
TagMonthlyStats AS (
    SELECT
        m.month_start,
        q.tag,
        COUNT(DISTINCT q.question_id)      AS questions_count,
        COUNT(a.answer_id)                 AS answers_count,
        AVG(a.answer_score)                AS avg_answer_score,
        percentile_cont(0.90) WITHIN GROUP (ORDER BY a.answer_score) AS p90_answer_score
      FROM Months m
      LEFT JOIN Questions q
        ON CAST(date_trunc('month', q.CreationDate) AS date) = m.month_start
      LEFT JOIN Answers a
        ON a.question_id = q.question_id
     GROUP BY m.month_start, q.tag
),
HotTags AS (
    SELECT
        tag,
        SUM(questions_count) AS total_questions,
        SUM(answers_count)   AS total_answers
      FROM TagMonthlyStats
     GROUP BY tag
    HAVING SUM(answers_count) > 500
),
TopBadges AS (
    SELECT
        b.UserId,
        b.Name       AS badge_name,
        COUNT(*)     AS badge_count,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC) AS rn
      FROM Badges b
     GROUP BY b.UserId, b.Name
    HAVING COUNT(*) > 5
)
SELECT
    ht.tag,
    ht.total_questions,
    ht.total_answers,
    tms.month_start,
    tms.questions_count,
    tms.answers_count,
    tms.avg_answer_score,
    tms.p90_answer_score,
    tb.badge_name    AS top_badge,
    tb.badge_count
FROM HotTags ht
JOIN TagMonthlyStats tms
  ON tms.tag = ht.tag
LEFT JOIN TopBadges tb
  ON tb.UserId = (
         SELECT p.OwnerUserId
           FROM Posts p
          WHERE p.PostTypeId = 2
            AND p.ParentId IN (
                 SELECT question_id
                   FROM Questions
                  WHERE tag = ht.tag
              )
          ORDER BY p.Score DESC
         LIMIT 1
     )
 AND tb.rn = 1
ORDER BY ht.total_answers DESC, tms.month_start DESC
LIMIT 100;