WITH
RecentQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.AccountId,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.CreationDate) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
TaggedMentions AS (
  SELECT
    p.Id AS PostId,
    -- normalize tag string like '<tag1><tag2>' into rows; uses standard SQL functions where available
    -- For portability, handle empty/null tags
    TRIM(t.tag) AS TagName
  FROM Posts p,
  LATERAL (
    SELECT regexp_split_to_table(
      CASE WHEN p.Tags IS NULL THEN '' ELSE substr(p.Tags, 2, length(p.Tags)-2) END,
      '><'
    ) AS tag
  ) t
  WHERE p.PostTypeId = 1
),
ExpandedPosts AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.Tags,
    rq.ViewCount,
    rq.Score,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.LastActivityDate,
    rq.ContentLicense,
    tm.TagName,
    tm.TagName AS TagOnly
  FROM RecentQuestions rq
  LEFT JOIN TaggedMentions tm ON rq.PostId = tm.PostId
),
MixedMetrics AS (
  SELECT
    e.PostId,
    e.Title,
    e.ViewCount,
    e.Score,
    e.CreationDate,
    e.OwnerUserId,
    e.LastActivityDate,
    e.ContentLicense,
    e.TagName,
    COALESCE( (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 8), 0 ) AS AvgBounty,
    COALESCE( (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 2), 0 ) AS UpModCount,
    COALESCE( (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 3), 0 ) AS DownModCount
  FROM ExpandedPosts e
)
SELECT
  m.PostId,
  m.Title,
  m.ViewCount,
  m.Score,
  m.CreationDate,
  m.OwnerUserId,
  m.LastActivityDate,
  m.ContentLicense,
  m.TagName AS Tag,
  m.AvgBounty,
  m.UpModCount,
  m.DownModCount,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  u.Location,
  u.WebsiteUrl,
  u.AboutMe,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.ProfileImageUrl
FROM MixedMetrics m
LEFT JOIN TopAuthors u ON m.OwnerUserId = u.UserId
WHERE
  m.TagName IS NOT NULL
  AND m.PostId IS NOT NULL
ORDER BY m.Score DESC, m.ViewCount DESC
LIMIT 100;