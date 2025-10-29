-- {"query": "5543.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 781} 
WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '60 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(p.Tags, '<>')) AS TagName,
    p.Id AS PostId,
    p.Score
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TagStats AS (
  SELECT
    TagName,
    COUNT(*) AS PostCount,
    AVG(Score) AS AvgScore,
    MAX(ViewCount) AS MaxViews
  FROM TopTags
  GROUP BY TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    ul.TagBased AS TagBadge
  FROM Users u
  LEFT JOIN Badges ul ON ul.UserId = u.Id AND ul.TagBased = 0
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
),
ImportantPostLinks AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Id IN (1, 3) -- Linked or Duplicate
),
QualifiedPosts AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AcceptedAnswerId,
    ro.OwnerUserId AS OwnerId,
    u.DisplayName AS OwnerDisplayName,
    JSON_BUILD_OBJECT(
      'created', rp.CreationDate,
      'lastActivity', rp.LastActivityDate,
      'score', rp.Score,
      'views', rp.ViewCount
    ) AS Meta
  FROM RecentActivePosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  LEFT JOIN Posts ro ON rp.Id = ro.Id
)
SELECT
  p.PostId,
  p.Title,
  p.Body,
  p.Tags,
  p.CreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  p.FavoriteCount,
  p.PostTypeId,
  p.AcceptedAnswerId,
  t.PostCount AS TagPostCount,
  t.AvgScore AS TagAvgScore,
  t.MaxViews AS TagMaxViews,
  u.OwnerId,
  u.OwnerDisplayName,
  u.Reputation,
  u.CreationDate AS OwnerCreationDate,
  u.LastAccessDate AS OwnerLastAccess,
  JSON_VALUE(p.Meta, '$.created') AS PostCreatedRaw
FROM QualifiedPosts p
LEFT JOIN TagStats t ON True
LEFT JOIN Users u ON p.OwnerId = u.Id
LEFT JOIN UserActivity ua ON u.Id = ua.UserId
ORDER BY p.LastActivityDate DESC, p.Score DESC
LIMIT 100;