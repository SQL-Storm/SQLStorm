WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.ContentLicense,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
tag_summary AS (
  SELECT
    tag AS TagName,
    COUNT(*) AS QuestionsWithTag,
    AVG(p.ViewCount) AS AvgViewsPerQuestion,
    SUM(p.Score) AS TotalScore
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id,
  LATERAL (
    SELECT UNNEST(STRING_TO_ARRAY(SUBSTR(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag
  ) t
  GROUP BY tag
),
top_tags AS (
  SELECT
    TagName,
    QuestionsWithTag,
    AvgViewsPerQuestion,
    TotalScore
  FROM tag_summary
  ORDER BY TotalScore DESC
  LIMIT 10
),
author_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsAsked,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersProvided,
    MAX(p.CreationDate) AS LastQuestionDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
correlated_comments AS (
  SELECT
    rq.PostId,
    c.Id AS CommentId,
    c.UserDisplayName,
    c.CreationDate,
    c.Score AS CommentScore,
    c.Text,
    CASE
      WHEN LOWER(c.Text) LIKE '%good%' THEN 1
      WHEN LOWER(c.Text) LIKE '%bad%' THEN -1
      ELSE 0
    END AS Sentiment
  FROM recent_questions rq
  LEFT JOIN Comments c ON c.PostId = rq.PostId
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14' DAY
),
complex_calc AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.ViewCount,
    rq.Score,
    rq.CommentCount,
    rq.AnswerCount,
    (rq.ViewCount * 1.0 / NULLIF(rq.AnswerCount, 0)) AS views_per_answer,
    (SELECT AVG(v.BountyAmount) FROM recent_votes v WHERE v.PostId = rq.PostId AND v.BountyAmount IS NOT NULL) AS AvgBounty
  FROM recent_questions rq
)
SELECT
  'Benchmark: 30d Questions, top tags, author activity, and sentiment' AS Col1,
  (SELECT COUNT(*) FROM recent_questions) AS Col2,
  (SELECT COUNT(*) FROM top_tags) AS Col3,
  (SELECT COUNT(*) FROM author_activity) AS Col4,
  (SELECT AVG(views_per_answer) FROM complex_calc) AS Col5,
  (SELECT AVG(AvgBounty) FROM complex_calc) AS Col6
UNION ALL
SELECT
  tg.TagName AS Col1,
  tg.QuestionsWithTag AS Col2,
  tg.AvgViewsPerQuestion AS Col3,
  tg.TotalScore AS Col4,
  NULL AS Col5,
  NULL AS Col6
FROM top_tags tg
ORDER BY Col4 DESC
LIMIT 5;