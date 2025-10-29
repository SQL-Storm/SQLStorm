-- {"query": "5160.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 537} 
WITH TrendingPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    p.OwnerUserId,
    ROW_NUMBER() OVER (
      ORDER BY
        p.Score * 2 + COALESCE(p.ViewCount,0) * 0.5
        + COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id),0)
        - COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id),0)
        DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.CreationDate >= DATEADD(day, -7, GETDATE())
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= DATEADD(day, -30, GETDATE())
    AND p.OwnerUserId IS NOT NULL
),
Aggregated AS (
  SELECT
    t.PostId,
    t.Title,
    t.Score,
    t.ViewCount,
    t.CreationDate,
    t.Tags,
    t.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = t.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = t.PostId) AS AnswerCount,
    -- windowed rank
    t.rn
  FROM TrendingPosts t
  JOIN Users u ON u.Id = t.OwnerUserId
  WHERE t.rn <= 100
),
HotTags AS (
  SELECT
    tg.TagName,
    COUNT(*) AS TagCount
  FROM Tags tg
  WHERE tg.Count > 0
  GROUP BY tg.TagName
  ORDER BY TagCount DESC
  LIMIT 5
)
SELECT
  a.PostId,
  a.Title,
  a.Score,
  a.ViewCount,
  a.CreationDate,
  a.Tags,
  a.OwnerUserId,
  a.DisplayName AS OwnerDisplayName,
  a.Reputation,
  a.CommentCount,
  a.AnswerCount,
  ht.TagName AS HotTag,
  a.TagCount
FROM Aggregated a
LEFT JOIN HotTags ht ON 1=1
ORDER BY a.rn, a.CreationDate DESC;