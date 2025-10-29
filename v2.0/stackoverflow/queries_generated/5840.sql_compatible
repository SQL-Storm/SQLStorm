WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  JOIN recent_questions rq ON rq.PostId = p.Id
  WHERE p.PostTypeId = 1
),
tag_agg AS (
  SELECT
    TagName,
    COUNT(*) AS QuestionCount,
    AVG(rq.Score) AS AvgScore,
    SUM(rq.ViewCount) AS TotalViews,
    MIN(rq.CreationDate) AS FirstQuestion
  FROM top_tags tt
  JOIN recent_questions rq ON rq.PostId = tt.PostId
  GROUP BY TagName
),
correlated_comments AS (
  SELECT
    c.PostId,
    AVG(CASE WHEN c.Text LIKE '%excellent%' THEN 1.0 ELSE 0 END) AS ExcellentMentionRate
  FROM Comments c
  GROUP BY c.PostId
),
combined AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.Score,
    rq.ViewCount,
    rq.Tags,
    rq.LastActivityDate,
    rq.CommentCount,
    rq.AnswerCount,
    rq.FavoriteCount,
    ca.ExcellentMentionRate
  FROM recent_questions rq
  LEFT JOIN correlated_comments ca ON ca.PostId = rq.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.LastActivityDate,
  c.CommentCount,
  c.AnswerCount,
  c.FavoriteCount,
  ca.ExcellentMentionRate,
  tt.TagName AS FocusTag,
  ta.QuestionCount,
  ta.AvgScore,
  ta.TotalViews,
  ta.FirstQuestion
FROM combined c
LEFT JOIN Users u ON u.Id = c.OwnerUserId
LEFT JOIN correlated_comments ca ON ca.PostId = c.PostId
LEFT JOIN (
  SELECT
    SUM(QuestionCount) AS QuestionCount,
    AVG(AvgScore) AS AvgScore,
    SUM(TotalViews) AS TotalViews,
    MIN(FirstQuestion) AS FirstQuestion
  FROM tag_agg
) ta ON true
LEFT JOIN LATERAL (
  SELECT TagName
  FROM tag_agg ta2
  ORDER BY ta2.QuestionCount DESC
  LIMIT 1
) tt ON true
WHERE
  c.CreationDate >= (SELECT MIN(CreationDate) FROM recent_questions)
GROUP BY
  c.PostId,
  c.Title,
  c.CreationDate,
  u.DisplayName,
  u.Reputation,
  c.Score,
  c.ViewCount,
  c.Tags,
  c.LastActivityDate,
  c.CommentCount,
  c.AnswerCount,
  c.FavoriteCount,
  ca.ExcellentMentionRate,
  tt.TagName,
  ta.QuestionCount,
  ta.AvgScore,
  ta.TotalViews,
  ta.FirstQuestion
ORDER BY c.LastActivityDate DESC
LIMIT 100;