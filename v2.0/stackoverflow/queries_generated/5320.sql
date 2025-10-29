-- {"query": "5320.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 737} 
WITH
 RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.PostTypeId
  FROM Posts p
  WHERE p.LastActivityDate > NOW() - INTERVAL '30 days'
),
 TagPopularity AS (
  SELECT
    unnest(string_to_array(p.Tags, '><')) AS tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
 Aggregated AS (
  SELECT
    t.tag AS Tag,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS Questions,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS Answers,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivity
  FROM TagPopularity t
  JOIN Posts p ON p.Tags LIKE '%' || t.tag || '%'
  GROUP BY t.tag
),
 Expanded AS (
  SELECT
    h.PostId,
    h.Title,
    h.CreationDate,
    h.LastActivityDate,
    h.Score,
    h.ViewCount,
    h.OwnerUserId,
    h.PostTypeId,
    a.Tag,
    ROW_NUMBER() OVER (
      PARTITION BY h.PostTypeId
      ORDER BY h.Score DESC, h.ViewCount DESC, h.LastActivityDate DESC
    ) AS rn
  FROM RecentHot h
  LEFT JOIN Posts p ON p.Id = h.Id
  LEFT JOIN Aggregated a ON a.Tag = ANY(string_to_array(p.Tags, '><'))
),
TopPosts AS (
  SELECT
    e.PostId,
    e.Title,
    e.CreationDate,
    e.LastActivityDate,
    e.Score,
    e.ViewCount,
    e.OwnerUserId,
    e.PostTypeId,
    e.Tag
  FROM Expanded e
  WHERE e.rn <= 5
),
ComplexFilters AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.LastActivityDate,
    tp.Score,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.PostTypeId,
    tp.Tag,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COALESCE(vt.Name, 'Unknown') AS VoteType,
    v.CreationDate AS VoteDate,
    v.BountyAmount
  FROM TopPosts tp
  LEFT JOIN Users u ON u.Id = tp.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = tp.PostId
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE tp.PostTypeId = 1
     OR tp.PostTypeId = 2
),
Final AS (
  SELECT
    cf.PostId,
    cf.Title,
    cf.CreationDate,
    cf.LastActivityDate,
    cf.Score,
    cf.ViewCount,
    cf.OwnerUserId,
    cf.PostTypeId,
    cf.Tag,
    cf.OwnerDisplayName,
    cf.Reputation,
    cf.VoteType,
    cf.VoteDate,
    cf.BountyAmount,
    CASE
      WHEN cf.Tag IS NULL THEN NULL
      ELSE UPPER(cf.Tag)
    END AS TagUpper
  FROM ComplexFilters cf
  ORDER BY cf.LastActivityDate DESC, cf.Score DESC NULLS LAST
)
SELECT *
FROM Final
LIMIT 100;