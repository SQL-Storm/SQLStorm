-- {"query": "5054.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 699}
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Body,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.CreationDate AS DATE)
      ORDER BY p.LastActivityDate DESC, p.Score DESC
    ) AS ActivityRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentTotal
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY)
    AND (p.ViewCount > 0 OR p.Score > 0)
),
Extended AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.OwnerUserId,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.Body,
    r.AnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    r.OwnerReputation,
    r.OwnerDisplayName,
    r.ActivityRank,
    r.CommentTotal,
    pl.RelatedPostId,
    pl.LinkTypeId,
    COUNT(pl2.Id) OVER (PARTITION BY r.PostId) AS LinkedCount
  FROM RankedPosts r
  LEFT JOIN PostLinks pl ON pl.PostId = r.PostId
  LEFT JOIN PostLinks pl2 ON pl2.PostId = r.PostId
  WHERE (pl.LinkTypeId IS NOT NULL OR pl2.LinkTypeId IS NOT NULL)
),
TagStats AS (
  SELECT
    e.PostId,
    e.Title,
    e.CreationDate,
    e.LastActivityDate,
    e.OwnerUserId,
    e.OwnerDisplayName,
    e.ActivityRank,
    e.CommentTotal,
    tag_name AS TagName,
    CAST(NULL AS INTEGER) AS TagCount,
    CAST(NULL AS BOOLEAN) AS IsModeratorOnly
  FROM Extended e
  CROSS JOIN LATERAL (
    SELECT trim(both ' ' FROM unnest_tags) AS tag_name
    FROM (
      SELECT regexp_split_to_table(replace(replace(e.Tags, '><', '>|<'), '><', '>|<') , '>|<') AS unnest_tags
    ) s
  ) tags
  WHERE e.PostTypeId = 1
),
Final AS (
  SELECT
    f.PostId,
    f.Title,
    f.OwnerDisplayName,
    f.OwnerReputation,
    f.ActivityRank,
    f.CommentTotal,
    ts.TagName,
    t2.Count AS TagCount,
    f.LinkTypeId,
    f.LinkedCount,
    f.LastActivityDate
  FROM Extended f
  LEFT JOIN TagStats ts ON ts.PostId = f.PostId
  LEFT JOIN Tags t2 ON t2.Id = (
    SELECT t3.Id FROM Tags t3 WHERE LOWER(t3.tagname) = LOWER(ts.TagName) LIMIT 1
  )
)
SELECT
  PostId,
  Title,
  OwnerDisplayName,
  OwnerReputation,
  ActivityRank,
  CommentTotal,
  TagName,
  TagCount,
  LinkTypeId,
  LinkedCount
FROM Final
WHERE TagName IS NOT NULL
ORDER BY ActivityRank ASC, LastActivityDate DESC
LIMIT 100;