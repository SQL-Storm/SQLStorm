-- {"query": "5009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 672} 
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
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
tag_stats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
    ON TRUE
  GROUP BY t.TagName
),
hot_candidates AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.CreationDate,
    rq.ViewCount,
    rq.Score,
    rq.AnswerCount,
    rq.CommentCount,
    rq.OwnerDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY rq.OwnerUserId
      ORDER BY rq.Score DESC, rq.ViewCount DESC, rq.CreationDate DESC
    ) AS rn_per_user
  FROM recent_questions rq
  LEFT JOIN Votes v ON v.PostId = rq.PostId
  WHERE rq.Score > 0
    AND rq.ViewCount > 100
)
SELECT
  h.PostId,
  h.Title,
  h.Tags,
  h.CreationDate,
  h.ViewCount,
  h.Score,
  h.AnswerCount,
  h.CommentCount,
  h.OwnerDisplayName,
  hs.TagName,
  ts.TagCount,
  ts.AvgScore AS TagAvgScore,
  ts.TotalViews AS TagTotalViews,
  CASE
    WHEN h.Score IS NULL THEN NULL
    ELSE h.Score * 0.5 + CASE WHEN h.ViewCount > 1000 THEN 100 ELSE 0 END
  END AS composite_metric,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = h.OwnerUserId AND p2.PostTypeId = 1) AS QuestionsByOwner,
  (SELECT AVG(Length(p.Body)) FROM Posts p WHERE p.OwnerUserId = h.OwnerUserId) AS AvgBodyLength
FROM hot_candidates h
LEFT JOIN tag_stats ts ON TRUE
LEFT JOIN UNNEST(string_to_array(substr(h.Tags, 2, length(h.Tags)-2), '><')) AS t(TagName)
  ON ts.TagName = t.TagName
GROUP BY
  h.PostId, h.Title, h.Tags, h.CreationDate, h.ViewCount, h.Score, h.AnswerCount,
  h.CommentCount, h.OwnerDisplayName, hs.TagName, ts.TagCount, ts.AvgScore, ts.TotalViews
ORDER BY
  h.Score DESC NULLS LAST,
  h.ViewCount DESC,
  h.CreationDate DESC
LIMIT 50;