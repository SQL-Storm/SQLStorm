-- {"query": "5540.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 769} 
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
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_summary AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    COUNT(*) AS QuestionsWithTag,
    AVG(p.ViewCount) AS AvgViewsPerQuestion,
    SUM(p.Score) AS TotalScore
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
  GROUP BY 1
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
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersProvided,
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
      WHEN c.Text ILIKE '%good%' THEN 1
      WHEN c.Text ILIKE '%bad%' THEN -1
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
  WHERE v.CreationDate >= NOW() - INTERVAL '14 days'
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
  'Benchmark: 30d Questions, top tags, author activity, and sentiment' AS BenchmarkLabel,
  (SELECT COUNT(*) FROM recent_questions) AS RecentQuestions,
  (SELECT COUNT(*) FROM top_tags) AS TopTagsCount,
  (SELECT COUNT(*) FROM author_activity) AS ActiveAuthors,
  (SELECT AVG(views_per_answer) FROM complex_calc) AS AvgViewsPerAnswer,
  (SELECT AVG(AvgBounty) FROM complex_calc) AS AvgBountyAcrossPosts
FROM dual
UNION ALL
SELECT
  tg.TagName,
  tg.QuestionsWithTag,
  tg.AvgViewsPerQuestion,
  tg.TotalScore
FROM top_tags tg
ORDER BY tg.TotalScore DESC
LIMIT 5
;