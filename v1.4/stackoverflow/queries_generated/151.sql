-- {"query": "151.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2280} 
WITH
RecentQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    (SELECT COUNT(*) FROM Posts AS a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Comments AS c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '2 years'
),
TagArrayLen AS (
  SELECT
    Id,
    Title,
    CreationDate,
    LastActivityDate,
    Score,
    ViewCount,
    OwnerUserId,
    Tags,
    AnswerCount,
    CommentCount,
    CASE
      WHEN Tags IS NULL THEN 0
      ELSE array_length(string_to_array(substring(Tags, 2, length(Tags) - 2), '><'), 1)
    END AS TagCount
  FROM RecentQuestions
),
OwnerInfo AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.AccountId,
    t.Title AS DummyDummy  -- placeholder to ensure non-empty projection for potential cross-DB compatibility
  FROM Users u
  LEFT JOIN TagArrayLen t ON t.OwnerUserId = u.Id
),
LinkedStats AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinkCount
  FROM PostLinks pl
  GROUP BY pl.PostId
),
GoldBadges AS (
  SELECT
    b.UserId,
    COUNT(*) AS GoldBadgeCount
  FROM Badges b
  WHERE b.Class = 1
  GROUP BY b.UserId
),
Final AS (
  SELECT
    q.Id,
    q.Title,
    q.CreationDate,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    o.DisplayName AS OwnerDisplayName,
    o.Reputation AS OwnerReputation,
    ls.LinkedCount,
    ls.DuplicateLinkCount,
    COALESCE(gb.GoldBadgeCount, 0) AS GoldBadgesOnOwner,
    ta.TagCount
  FROM TagArrayLen q
  LEFT JOIN Users o ON o.Id = q.OwnerUserId
  LEFT JOIN LinkedStats ls ON ls.PostId = q.Id
  LEFT JOIN GoldBadges gb ON gb.UserId = o.Id
  WHERE q.TagCount IS NOT NULL OR q.TagCount >= 0
),
Ranked AS (
  SELECT
    f.*,
    ROW_NUMBER() OVER (PARTITION BY OwnerDisplayName ORDER BY Score DESC, CreationDate DESC) AS rn
  FROM Final f
)
SELECT
  Id,
  Title,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  OwnerDisplayName,
  OwnerReputation,
  LinkedCount,
  DuplicateLinkCount,
  GoldBadgesOnOwner,
  TagCount
FROM Ranked
WHERE rn <= 3
ORDER BY OwnerDisplayName, Score DESC, CreationDate DESC

UNION ALL

WITH
WikiQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    (SELECT COUNT(*) FROM Posts AS a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Comments AS c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 4 OR p.PostTypeId = 5
),
WikiTagStats AS (
  SELECT
    w.Id,
    w.Title,
    w.CreationDate,
    w.LastActivityDate,
    w.Score,
    w.ViewCount,
    w.OwnerUserId,
    w.Tags,
    (SELECT COUNT(*) FROM Posts AS a WHERE a.ParentId = w.Id AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Comments AS c WHERE c.PostId = w.Id) AS CommentCount,
    CASE
      WHEN w.Tags IS NULL THEN 0
      ELSE array_length(string_to_array(substring(w.Tags, 2, length(w.Tags) - 2), '><'), 1)
    END AS TagCount
  FROM WikiQuestions w
),
WikiOwners AS (
  SELECT
    wu.Id AS PostId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    wu.Title,
    wu.CreationDate,
    wu.LastActivityDate,
    wu.Score,
    wu.ViewCount,
    wu.Tags,
    wu.TagCount
  FROM WikiTagStats wu
  LEFT JOIN Users u ON u.Id = wu.OwnerUserId
)
SELECT
  PostId AS Id,
  Title,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  OwnerDisplayName,
  OwnerReputation,
  TagCount
FROM WikiOwners
ORDER BY OwnerDisplayName, Score DESC, CreationDate DESC
LIMIT 0;