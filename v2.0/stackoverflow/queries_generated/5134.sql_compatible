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
  WHERE t.IsModeratorOnly = FALSE
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
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.Score,
    c.ViewCount,
    c.OwnerUserId,
    c.OwnerDisplayName,
    c.LastActivityDate,
    c.CommentCount,
    c.FavoriteCount,
    c.ContentLicense,
    c.TagName,
    c.Count,
    c.ExcerptPostId,
    c.WikiPostId,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = c.OwnerUserId AND p2.PostTypeId = 1 AND p2.CreationDate >= c.CreationDate - INTERVAL '30 days') AS AvgOwner30dScore,
    (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = c.PostId) AS CommentCountPost,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 8) AS TotalBounty
  FROM Combined c
),
Windowed AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.Score,
    c.ViewCount,
    c.OwnerUserId,
    c.OwnerDisplayName,
    c.LastActivityDate,
    c.CommentCount,
    c.FavoriteCount,
    c.ContentLicense,
    c.TagName,
    c.Count,
    c.ExcerptPostId,
    c.WikiPostId,
    c.AvgOwner30dScore,
    c.CommentCountPost,
    c.TotalBounty,
    SUM(c.Score) OVER (PARTITION BY c.OwnerUserId ORDER BY c.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS Rolling30dScore,
    COUNT(*) OVER (PARTITION BY c.OwnerUserId) AS PostsPerAuthor
  FROM Correlated c
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
ORDER BY Rolling30dScore DESC, ViewCount DESC, Score DESC
LIMIT 100;