-- {"query": "5840.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 609} 
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
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
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
  JOIN recent_questions rq ON true
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
LEFT JOIN tag_agg ta ON true
LEFT JOIN LATERAL (
  SELECT TOP 1 TagName
  FROM tag_agg ta2
  ORDER BY ta2.QuestionCount DESC
) tt ON true
WHERE
  c.CreationDate >= (SELECT MIN(CreationDate) FROM recent_questions)
ORDER BY c.LastActivityDate DESC
LIMIT 100;