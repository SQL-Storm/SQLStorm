-- {"query": "369.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 22920} 
WITH
TopScore AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    COALESCE(u.DisplayName, 'Unknown') AS OwnerName,
    CASE
      WHEN p.Tags IS NULL THEN ARRAY[]::text[]
      ELSE (SELECT string_to_array(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><'))
    END AS TagNames,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId), 0) AS OwnerBadges,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
TopViewed AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    COALESCE(u.DisplayName, 'Unknown') AS OwnerName,
    CASE
      WHEN p.Tags IS NULL THEN ARRAY[]::text[]
      ELSE (SELECT string_to_array(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><'))
    END AS TagNames,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId), 0) AS OwnerBadges,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS OwnerRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
)
SELECT
  t.PostId,
  t.Title,
  t.CreationDate,
  t.Score,
  t.ViewCount,
  t.TagNames,
  t.OwnerUserId,
  t.OwnerName,
  t.CommentCount,
  t.OwnerBadges,
  t.OwnerRank
FROM TopScore t
WHERE t.OwnerRank <= 10
UNION ALL
SELECT
  v.PostId,
  v.Title,
  v.CreationDate,
  v.Score,
  v.ViewCount,
  v.TagNames,
  v.OwnerUserId,
  v.OwnerName,
  v.CommentCount,
  v.OwnerBadges,
  v.OwnerRank
FROM TopViewed v
WHERE v.OwnerRank <= 15
ORDER BY Score DESC, ViewCount DESC
LIMIT 50;