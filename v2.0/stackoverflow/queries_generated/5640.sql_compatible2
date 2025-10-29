WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
TopAuthors AS (
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
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
  WHERE u.Reputation IS NOT NULL
),
TagExtract AS (
  SELECT
    p.PostId,
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  FROM RecentActivePosts p
  WHERE p.Tags IS NOT NULL
),
LinkStats AS (
  SELECT
    pl.RelatedPostId AS PostId,
    COUNT(*) AS LinkCount
  FROM PostLinks pl
  GROUP BY pl.RelatedPostId
),
CommentStats AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
VoteAgg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS Deletions,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts
  FROM Votes v
  GROUP BY v.PostId
),
CTE AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.OwnerUserId,
    r.Tags,
    r.ViewCount,
    r.Score,
    COALESCE(cs.CommentCount, 0) AS CommentCount,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    COALESCE(la.LinkCount, 0) AS LinkCount,
    COALESCE(ta.TagName, '') AS PrimaryTag,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Location
  FROM RecentActivePosts r
  LEFT JOIN CommentStats cs ON cs.PostId = r.PostId
  LEFT JOIN VoteAgg va ON va.PostId = r.PostId
  LEFT JOIN LinkStats la ON la.PostId = r.PostId
  LEFT JOIN TagExtract ta ON ta.PostId = r.PostId
  LEFT JOIN Users u ON u.Id = r.OwnerUserId
)
SELECT
  c.PostId,
  c.PostTypeId,
  ptype.Name AS PostType,
  c.Title,
  c.OwnerUserId,
  cu.DisplayName AS OwnerDisplayName,
  (c.OwnerUserId IS NULL) AS IsAnonymous,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount AS ViewCount,
  c.Score,
  c.CommentCount,
  c.UpVotes,
  c.DownVotes,
  c.LinkCount,
  c.PrimaryTag,
  c.Reputation,
  c.Location,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName <> '') AS TagsList
FROM CTE c
LEFT JOIN PostTypes ptype ON ptype.Id = c.PostTypeId
LEFT JOIN TopAuthors cu ON cu.UserId = c.OwnerUserId
LEFT JOIN Tags t ON t.Id = (
  SELECT tt.Id FROM Tags tt WHERE tt.TagName = c.PrimaryTag LIMIT 1
)
GROUP BY
  c.PostId,
  c.PostTypeId,
  ptype.Name,
  c.Title,
  c.OwnerUserId,
  cu.DisplayName,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  c.UpVotes,
  c.DownVotes,
  c.LinkCount,
  c.PrimaryTag,
  c.Reputation,
  c.Location
ORDER BY c.LastActivityDate DESC
LIMIT 200;