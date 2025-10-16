-- {"query": "9011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 4380} 

WITH
-- Aggregate badge counts and rank users by reputation
UserStats AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS RepRank,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Users AS u
  LEFT JOIN Badges AS b
    ON b.UserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation
),

-- Count answers per question and compute basic answer‐score stats
QuestionAnswerStats AS (
  SELECT
    q.Id    AS QId,
    COUNT(a.Id)                                 AS AnswerCount,
    MAX(a.Score)                                AS TopAnswerScore,
    AVG(a.Score)    FILTER (WHERE a.Score >= 0) AS AvgPositiveScore,
    COUNT(*)        FILTER (WHERE a.Score <  0) AS NegAnswerCount
  FROM Posts AS q
  LEFT JOIN Posts AS a
    ON a.ParentId = q.Id
   AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
  GROUP BY q.Id
),

-- Split the Tags string into individual tag rows
TagList AS (
  SELECT
    q.Id AS QId,
    TRIM(t.tag) AS Tag
  FROM Posts AS q
  CROSS JOIN LATERAL
    UNNEST(
      string_to_array(
        substring(q.Tags FROM 2 FOR char_length(q.Tags)-2),
        '><'
      )
    ) AS t(tag)
  WHERE q.PostTypeId = 1
    AND q.Tags IS NOT NULL
),

-- Aggregate per‐tag question counts, average score, and total views
TagStats AS (
  SELECT
    tl.Tag,
    COUNT(*)     AS Questions,
    AVG(q.Score) AS AvgScore,
    SUM(q.ViewCount) AS TotalViews
  FROM TagList AS tl
  JOIN Posts AS q
    ON q.Id = tl.QId
  GROUP BY tl.Tag
)

-- Main result combining users, their questions, answer stats, and tag stats,
-- then a UNION ALL for users with no questions, finally EXCEPT to filter out
-- a subset for added complexity.
SELECT
  us.DisplayName,
  us.Reputation,
  us.RepRank,
  qs.AnswerCount,
  qs.TopAnswerScore,
  ts.Tag,
  CASE
    WHEN ts.AvgScore IS NULL THEN 'N/A'
    ELSE TO_CHAR(ts.AvgScore,'FM999.00')
  END AS AvgTagScore,
  EXTRACT(EPOCH FROM (NOW() - q.CreationDate)) / 86400 AS DaysSinceQuestion,
  COALESCE(
    (
      SELECT COUNT(*)
      FROM Comments AS c
      WHERE c.UserId = us.Id
        AND c.CreationDate > us.LastAccessDate
    ),
    0
  ) AS LateComments
FROM UserStats AS us
JOIN Posts AS q
  ON q.OwnerUserId = us.Id
 AND q.PostTypeId = 1
JOIN QuestionAnswerStats AS qs
  ON qs.QId = q.Id
LEFT JOIN TagStats AS ts
  ON EXISTS (
       SELECT 1
       FROM TagList AS tl
       WHERE tl.QId = q.Id
         AND tl.Tag = ts.Tag
     )
WHERE us.Reputation > (SELECT AVG(Reputation) FROM Users)
  AND EXISTS (
    SELECT 1
    FROM Votes AS v
    WHERE v.UserId = us.Id
      AND v.VoteTypeId = 2
  )

UNION ALL

SELECT
  u.DisplayName,
  u.Reputation,
  NULL       AS RepRank,
  0          AS AnswerCount,
  NULL       AS TopAnswerScore,
  'no-tag'   AS Tag,
  '0.00'     AS AvgTagScore,
  0          AS DaysSinceQuestion,
  0          AS LateComments
FROM Users AS u
WHERE u.Id NOT IN (SELECT us.Id FROM UserStats AS us)

EXCEPT

SELECT
  us.DisplayName,
  us.Reputation,
  us.RepRank,
  qs.AnswerCount,
  qs.TopAnswerScore,
  ts.Tag,
  TO_CHAR(ts.AvgScore,'FM999.00'),
  EXTRACT(EPOCH FROM (NOW() - q.CreationDate)) / 86400,
  COALESCE(
    (
      SELECT COUNT(*)
      FROM Comments AS c
      WHERE c.UserId = us.Id
    ),
    0
  )
FROM UserStats AS us
JOIN Posts AS q
  ON q.OwnerUserId = us.Id
 AND q.PostTypeId = 1
JOIN QuestionAnswerStats AS qs
  ON qs.QId = q.Id
JOIN TagStats AS ts
  ON EXISTS (
       SELECT 1
       FROM TagList AS tl
       WHERE tl.QId = q.Id
         AND tl.Tag = ts.Tag
     )
ORDER BY Reputation DESC;
