-- {"query": "5267.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 683}
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate IS NOT NULL
),
TagPopularity AS (
  SELECT
    tag AS TagName,
    p.PostId,
    p.Score,
    p.ViewCount
  FROM RecentActivePosts p,
  LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
  ) t
),
TopTags AS (
  SELECT
    TagName,
    COUNT(*) AS PostCount,
    AVG(Score) AS AvgScore,
    SUM(ViewCount) AS TotalViews
  FROM TagPopularity
  GROUP BY TagName
  HAVING COUNT(*) > 5
),
CorrelatedStats AS (
  SELECT
    r.PostId,
    r.Title,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    t.TagName,
    tt.AvgScore,
    tt.TotalViews
  FROM RecentActivePosts r
  LEFT JOIN LATERAL (
    SELECT tp.TagName
    FROM TagPopularity tp
    WHERE tp.PostId = r.PostId
    ORDER BY tp.TagName
    LIMIT 1
  ) AS t ON TRUE
  LEFT JOIN TopTags tt ON tt.TagName = t.TagName
),
ExtremeActivity AS (
  SELECT
    c.PostId,
    c.Title,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.TagName,
    c.AvgScore,
    c.TotalViews,
    CASE
      WHEN c.LastActivityDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days') THEN 1
      ELSE 0
    END AS RecentlyActive
  FROM CorrelatedStats c
  WHERE c.ViewCount > 1000
    OR c.Score > 20
    OR (c.TagName IS NOT NULL AND c.TotalViews > 5000)
)
SELECT
  e.PostId,
  e.Title,
  e.LastActivityDate,
  e.Score,
  e.ViewCount,
  e.TagName,
  e.AvgScore,
  e.TotalViews,
  e.RecentlyActive,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 2) AS UpvotesToday,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 3) AS DownvotesToday,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = e.PostId) AS CommentCountTotal,
  (SELECT AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END) FROM Votes v WHERE v.PostId = e.PostId) AS AvgUpMod
FROM ExtremeActivity e
ORDER BY e.LastActivityDate DESC, e.TotalViews DESC
LIMIT 100;