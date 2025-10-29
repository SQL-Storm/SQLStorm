-- {"query": "5045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 715}
WITH recent_high_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.PostTypeId,
    ua.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY CAST(DATE_TRUNC('hour', p.CreationDate) AS timestamp) ORDER BY p.Score DESC, p.ViewCount DESC) AS HrRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users ua ON p.OwnerUserId = ua.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days'
),
tag_impact AS (
  SELECT
    p.Id AS PostId,
    TRIM(x.tag) AS TagName,
    p.Score,
    p.ViewCount
  FROM Posts p,
  LATERAL (
    SELECT regexp_split_to_table(
      regexp_replace(p.Tags, '^<|>$', '', 'g'),
      '><'
    ) AS tag
  ) x
  WHERE p.PostTypeId = 1
),
tag_summary AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(t.Score) AS AvgScore,
    AVG(t.ViewCount) AS AvgViews
  FROM tag_impact t
  GROUP BY t.TagName
),
cross_ref AS (
  SELECT
    pr.PostId,
    pr.RelatedPostId,
    lt.Name AS LinkType
  FROM PostLinks pr
  JOIN LinkTypes lt ON pr.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked','Duplicate')
),
hot_tags AS (
  SELECT
    t.TagName,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.Score) AS TotalScore
  FROM tag_impact t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
  ORDER BY SUM(p.ViewCount) DESC
  LIMIT 5
)
SELECT
  rha.PostId,
  rha.Title,
  rha.Tags,
  rha.CreationDate,
  rha.OwnerDisplayName,
  rha.OwnerReputation,
  rha.ViewCount,
  rha.Score,
  rha.AnswerCount,
  rha.CommentCount,
  rha.LastActivityDate,
  rha.PostTypeId,
  rha.HrRank,
  ts.PostCount AS TagPostCount,
  ts.AvgScore AS TagAvgScore,
  ts.AvgViews AS TagAvgViews,
  cr.RelatedPostId,
  cr.LinkType,
  ht.TagName AS HotTag,
  ht.TotalViews AS HotTagViews,
  ht.TotalScore AS HotTagScore
FROM recent_high_activity rha
LEFT JOIN tag_summary ts ON POSITION(ts.TagName IN rha.Tags) > 0
LEFT JOIN cross_ref cr ON cr.PostId = rha.PostId
LEFT JOIN hot_tags ht ON ht.TagName = (
  SELECT t.tag FROM (
    SELECT regexp_split_to_table(regexp_replace(rha.Tags, '^<|>$', '', 'g'), '><') AS tag
  ) t
  LIMIT 1
)
WHERE rha.HrRank <= 100
ORDER BY rha.CreationDate DESC, rha.Score DESC
LIMIT 200;