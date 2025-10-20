WITH
  QuestionTags AS (
    SELECT
      p.Id AS question_id,
      p.OwnerUserId,
      t.tag
    FROM Posts p,
    LATERAL (
      SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
    ) t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
  ),
  TagStats AS (
    SELECT
      qt.tag,
      COUNT(*)               AS question_count,
      AVG(p.Score)           AS avg_score,
      SUM(p.ViewCount)       AS total_views
    FROM QuestionTags qt
    JOIN Posts p ON p.Id = qt.question_id
    GROUP BY qt.tag
  ),
  TopContributors AS (
    SELECT
      tag,
      OwnerUserId AS user_id,
      contributions
    FROM (
      SELECT
        qt.tag,
        p.OwnerUserId,
        COUNT(*)                                  AS contributions,
        ROW_NUMBER() OVER (PARTITION BY qt.tag
                           ORDER BY COUNT(*) DESC) AS rn
      FROM QuestionTags qt
      JOIN Posts p ON p.Id = qt.question_id
      GROUP BY qt.tag, p.OwnerUserId
    ) x
    WHERE rn = 1
  ),
  BadgeCounts AS (
    SELECT
      UserId AS user_id,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM Badges
    GROUP BY UserId
  ),
  AnswerStats AS (
    SELECT
      qt.tag,
      a.OwnerUserId                                    AS user_id,
      AVG(a.Score)                                     AS avg_answer_score,
      AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) / 3600.0 AS avg_answer_time_hours
    FROM Posts a
    JOIN Posts q ON q.AcceptedAnswerId = a.Id
    JOIN QuestionTags qt ON qt.question_id = q.Id
    GROUP BY qt.tag, a.OwnerUserId
  )
SELECT
  ts.tag,
  ts.question_count,
  ts.avg_score,
  ts.total_views,
  tc.user_id,
  u.DisplayName,
  COALESCE(bc.gold_badges, 0)   AS gold_badges,
  COALESCE(bc.silver_badges, 0) AS silver_badges,
  COALESCE(bc.bronze_badges, 0) AS bronze_badges,
  COALESCE(ans.avg_answer_score, 0)       AS avg_answer_score,
  COALESCE(ans.avg_answer_time_hours, 0)  AS avg_answer_time_hours,
  (
    CAST(ts.question_count AS numeric) / NULLIF(ts.avg_score, 0)
  )
  + COALESCE(bc.gold_badges, 0) * 5
  + COALESCE(ans.avg_answer_score, 0)
  - COALESCE(ans.avg_answer_time_hours, 0) / 24.0 AS composite_metric
FROM TagStats ts
JOIN TopContributors tc
  ON tc.tag = ts.tag
JOIN Users u
  ON u.Id = tc.user_id
LEFT JOIN BadgeCounts bc
  ON bc.user_id = u.Id
LEFT JOIN AnswerStats ans
  ON ans.tag = ts.tag
 AND ans.user_id = u.Id
GROUP BY
  ts.tag,
  ts.question_count,
  ts.avg_score,
  ts.total_views,
  tc.user_id,
  u.DisplayName,
  bc.gold_badges,
  bc.silver_badges,
  bc.bronze_badges,
  ans.avg_answer_score,
  ans.avg_answer_time_hours
ORDER BY composite_metric DESC
LIMIT 10;