-- {"query": "5420.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 685} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName,
    p.Id AS PostId,
    p.Score,
    p.ViewCount
  FROM RecentActivePosts p
),
TagStats AS (
  SELECT
    TagName,
    COUNT(*) AS PostCount,
    AVG(Score) AS AvgScore,
    SUM(ViewCount) AS TotalViews
  FROM TopTags
  GROUP BY TagName
),
QualifiedPosts AS (
  SELECT
    rp.Id AS PostId,
    rp.Title,
    rp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.Tags,
    tt.TagName
  FROM RecentActivePosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN TopTags tt ON rp.Id = tt.PostId
  LEFT JOIN TagStats ts ON tt.TagName = ts.TagName
  WHERE rp.PostTypeId = 1 -- questions
    AND rp.OwnerUserId IS NOT NULL
    AND rp.Score > 0
    AND rp.ViewCount > 50
),
ComplexCoalesced AS (
  SELECT
    p.PostId,
    p.Title,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Tags,
    p.TagName,
    CASE
      WHEN p.TagName IS NULL THEN NULL
      ELSE CONCAT(p.Title, ' [', p.TagName, ']')
    END AS TitleWithTag,
    ROW_NUMBER() OVER (
      PARTITION BY p.TagName
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn_per_tag
  FROM QualifiedPosts p
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.CreationDate,
  c.LastActivityDate,
  c.Score,
  c.ViewCount,
  c.CommentCount,
  c.AnswerCount,
  c.FavoriteCount,
  c.Tags,
  c.TagName,
  c.TitleWithTag,
  c.rn_per_tag
FROM ComplexCoalesced c
WHERE c.rn_per_tag = 1
ORDER BY
  c.TagName NULLS LAST,
  c.Score DESC,
  c.ViewCount DESC,
  c.LastActivityDate DESC
LIMIT 100;