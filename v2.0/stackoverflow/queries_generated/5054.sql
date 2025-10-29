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
    -- Window function: relative activity rank per day
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.CreationDate AS DATE)
      ORDER BY p.LastActivityDate DESC, p.Score DESC
    ) AS ActivityRank,
    -- Small correlated subquery: total comments on the post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentTotal
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
    AND (p.ViewCount > 0 OR p.Score > 0)
),
Extended AS (
  SELECT
    r.*,
    -- Outer join example: newest related posts via PostLinks
    pl.RelatedPostId,
    pl.LinkTypeId,
    -- Aggregate: count of linked posts by type per post
    COUNT(pl2.Id) OVER (PARTITION BY r.PostId) AS LinkedCount
  FROM RankedPosts r
  LEFT JOIN PostLinks pl ON pl.PostId = r.PostId
  LEFT JOIN PostLinks pl2 ON pl2.PostId = r.PostId
  WHERE pl.LinkTypeId IS NOT NULL OR pl2.LinkTypeId IS NOT NULL
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
    t.TagName,
    t.Count AS TagCount,
    t.IsModeratorOnly
  FROM Extended e
  LEFT JOIN UNNEST(string_to_array(e.Tags, '> <')) AS t(TagName) ON TRUE
  LEFT JOIN Tags t ON t.TagName = trim(both ' ' FROM replace(replace(replace(e.Tags, '<', ''), '>', ''), ' ', ''))
  WHERE e.PostTypeId = 1 -- only questions for tag analytics
),
Final AS (
  SELECT
    f.PostId,
    f.Title,
    f.OwnerDisplayName,
    f.OwnerReputation,
    f.ActivityRank,
    f.CommentTotal,
    f.TagName,
    f.TagCount,
    f.LinkTypeId,
    f.LinkedCount
  FROM Extended f
  LEFT JOIN Tags t ON t.Id = (SELECT Id FROM Tags t2 WHERE t2.TagName = f.TagName LIMIT 1)
  ORDER BY f.ActivityRank ASC, f.LastActivityDate DESC NULLS LAST
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
LIMIT 100;