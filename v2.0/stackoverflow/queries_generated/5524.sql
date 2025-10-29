-- {"query": "5524.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 594} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2)
),
TopPosts AS (
  SELECT *
  FROM RankedPosts
  WHERE rn <= 5
),
RecentActivity AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.PostTypeId
  FROM Posts p
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TagAnalytics AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
    COUNT(*) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY Tag
)
SELECT
  tp.Id AS PostId,
  tp.Title,
  tp.PostTypeId,
  tp.CreationDate,
  tp.LastActivityDate,
  tp.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  tp.Score,
  tp.ViewCount,
  tp.Tags,
  ra.Title AS RecentSiblingTitle,
  ra.CreationDate AS RecentSiblingCreationDate,
  ra.Score AS RecentSiblingScore,
  ta.Tag AS TopTag,
  ta.PostCount AS TagPostCount,
  ta.TotalViews AS TagTotalViews,
  ta.AvgScore AS TagAvgScore,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Votes v
      WHERE v.PostId = tp.Id AND v.VoteTypeId = 2
        AND v.UserId = (SELECT MAX(Id) FROM Users)
    ) THEN true
    ELSE false
  END AS HasMostActiveVoter
FROM TopPosts tp
LEFT JOIN Users u ON tp.OwnerUserId = u.Id
LEFT JOIN Posts ra ON ra.ParentId = tp.Id AND ra.PostTypeId = 2
LEFT JOIN RecentActivity ra ON ra.Id = ra.Id
LEFT JOIN TagAnalytics ta ON true
WHERE tp.PostTypeId = 1
ORDER BY tp.Score DESC, tp.ViewCount DESC
LIMIT 100;