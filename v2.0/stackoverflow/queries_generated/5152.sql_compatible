WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
ActivePostOwners AS (
  SELECT
    rap.PostId,
    rap.OwnerUserId,
    u.DisplayName AS OwnerName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl
  FROM RecentActivePosts rap
  LEFT JOIN Users u ON rap.OwnerUserId = u.Id
),
TopTags AS (
  SELECT
    unnest(string_to_array(rap.Tags, '><')) AS TagName,
    rap.PostId
  FROM RecentActivePosts rap
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(rap.Score) AS AvgScore,
    SUM(rap.ViewCount) AS TotalViews
  FROM TopTags t
  JOIN RecentActivePosts rap ON t.PostId = rap.PostId
  GROUP BY t.TagName
),
TagCoOccurrence AS (
  SELECT
    a.PostId,
    b.PostId AS RelatedPostId,
    a.Tags AS TagsA,
    b.Tags AS TagsB
  FROM RecentActivePosts a
  JOIN RecentActivePosts b
    ON a.PostId <> b.PostId
  WHERE a.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '60 days'
    AND b.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '60 days'
),
WindowedPosts AS (
  SELECT
    a.PostId,
    a.PostTypeId,
    a.Title,
    a.OwnerUserId,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY a.PostTypeId ORDER BY a.Score DESC, a.ViewCount DESC) AS RNByType
  FROM RecentActivePosts a
),
CorrelatedSubq AS (
  SELECT
    w.PostId,
    w.Title,
    w.OwnerUserId,
    w.CreationDate,
    w.LastActivityDate,
    w.Score,
    w.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = w.PostId AND c.Score > 0) AS PositiveComments
  FROM WindowedPosts w
  WHERE w.RNByType <= 10
)
SELECT
  cs.PostId,
  cs.Title,
  cs.OwnerUserId,
  ou.OwnerName,
  ou.Reputation,
  cs.CreationDate,
  cs.LastActivityDate,
  cs.Score,
  cs.ViewCount,
  cs.PositiveComments,
  COALESCE(t.TagName, 'Unknown') AS TagName,
  COALESCE(vt.Name, 'Unknown') AS VoteTypeName,
  u.Location,
  u.WebsiteUrl
FROM CorrelatedSubq cs
JOIN ActivePostOwners ou ON cs.PostId = ou.PostId
LEFT JOIN LATERAL (
  SELECT t0.TagName
  FROM unnest(string_to_array(ou.OwnerName || ' ' || cs.Title, ' ')) AS t0(TagName)
  WHERE t0.TagName <> ''
  LIMIT 1
) t ON TRUE
LEFT JOIN Votes v ON v.PostId = cs.PostId
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN Users u ON ou.OwnerUserId = u.Id
GROUP BY
  cs.PostId,
  cs.Title,
  cs.OwnerUserId,
  ou.OwnerName,
  ou.Reputation,
  cs.CreationDate,
  cs.LastActivityDate,
  cs.Score,
  cs.ViewCount,
  cs.PositiveComments,
  t.TagName,
  vt.Name,
  u.Location,
  u.WebsiteUrl
ORDER BY cs.LastActivityDate DESC, cs.Score DESC
LIMIT 100;