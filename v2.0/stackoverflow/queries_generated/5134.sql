-- {"query": "5134.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 856} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions only
    AND p.ClosedDate IS NULL
),
TagEngagement AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    p.Id AS PostId
  FROM Tags t
  LEFT JOIN Posts p ON t.WikiPostId = p.Id
  WHERE t.IsModeratorOnly = 0
),
Combined AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.OwnerDisplayName,
    r.LastActivityDate,
    r.CommentCount,
    r.FavoriteCount,
    r.ContentLicense,
    te.TagName,
    te.Count,
    te.ExcerptPostId,
    te.WikiPostId
  FROM RecentHot r
  LEFT JOIN TagEngagement te ON r.PostId = te.PostId
),
Correlated AS (
  SELECT
    c.*,
    (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = c.OwnerUserId AND p2.PostTypeId = 1 AND p2.CreationDate >= c.CreationDate - INTERVAL '30 days') AS AvgOwner30dScore,
    (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = c.PostId) AS CommentCountPost,
    (SELECT SUM(BountyAmount) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 8) AS TotalBounty
  FROM Combined c
),
Windowed AS (
  SELECT
    Correlated.*,
    SUM(Score) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS Rolling30dScore,
    COUNT(*) OVER (PARTITION BY OwnerUserId) AS PostsPerAuthor
  FROM Correlated
),
Final AS (
  SELECT
    w.PostId,
    w.Title,
    w.Tags,
    w.CreationDate,
    w.Score,
    w.ViewCount,
    w.OwnerUserId,
    u.DisplayName AS OwnerDisplayNameFromUsers,
    w.LastActivityDate,
    w.CommentCount,
    w.FavoriteCount,
    w.ContentLicense,
    w.TagName,
    w.Count AS TagCount,
    w.ExcerptPostId,
    w.WikiPostId,
    w.AvgOwner30dScore,
    w.CommentCountPost,
    w.TotalBounty,
    w.Rolling30dScore,
    w.PostsPerAuthor,
    CASE
      WHEN w.Score >= 10 THEN 'Hot'
      WHEN w.ViewCount > 1000 THEN 'Popular'
      ELSE 'Normal'
    END AS RankingBucket
  FROM Windowed w
  LEFT JOIN Users u ON w.OwnerUserId = u.Id
)
SELECT
  PostId,
  Title,
  Tags,
  CreationDate,
  Score,
  ViewCount,
  OwnerUserId,
  OwnerDisplayNameFromUsers AS OwnerDisplayName,
  LastActivityDate,
  CommentCount,
  FavoriteCount,
  ContentLicense,
  TagName,
  TagCount,
  ExcerptPostId,
  WikiPostId,
  AvgOwner30dScore,
  CommentCountPost,
  TotalBounty,
  Rolling30dScore,
  PostsPerAuthor,
  RankingBucket
FROM Final
WHERE Rolling30dScore > 0
ORDER BY Rolling30dScore DESC NULLS LAST, ViewCount DESC, Score DESC
LIMIT 100;