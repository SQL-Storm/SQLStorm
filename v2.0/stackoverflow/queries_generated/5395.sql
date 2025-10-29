-- {"query": "5395.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 512} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.DeletionDate IS NULL
),
top_tags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
  FROM Posts p
  WHERE p.Id IN (SELECT PostId FROM recent_questions)
),
tag_rank AS (
  SELECT
    Tag,
    COUNT(*) AS TagCount
  FROM top_tags
  GROUP BY Tag
),
avg_metrics AS (
  SELECT
    AVG(p.Score) AS avg_score,
    AVG(p.ViewCount) AS avg_views,
    AVG(p.CommentCount) AS avg_comments,
    AVG(p.AnswerCount) AS avg_answers
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  rq.PostId,
  rq.Title,
  rq.Tags,
  rq.CreationDate,
  rq.Score,
  rq.ViewCount,
  rq.OwnerUserId,
  rq.LastActivityDate,
  rq.CommentCount,
  rq.AnswerCount,
  rq.FavoriteCount,
  rq.ContentLicense,
  tr.Tag AS TagName,
  tr.TagCount,
  rt.avg_score,
  rt.avg_views,
  rt.avg_comments,
  rt.avg_answers,
  -- Window-based rankings: rank questions by Score within recent 1000 hrs per tag
  RANK() OVER (
    PARTITION BY tr.Tag
    ORDER BY rq.Score DESC NULLS LAST, rq.ViewCount DESC NULLS LAST
  ) AS score_rank
FROM recent_questions rq
LEFT JOIN (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
) t ON t.PostId = rq.PostId
LEFT JOIN TagRankView tr ON tr.Tag = t.Tag
LEFT JOIN avg_metrics rt ON 1=1
ORDER BY score_rank, rq.CreationDate DESC
LIMIT 100;