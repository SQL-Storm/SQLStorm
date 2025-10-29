WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_owner
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
TagUsage AS (
  SELECT
    tag AS TagName,
    COUNT(*) AS TagCount
  FROM (
    SELECT
      -- split tags like "<tag1><tag2>" into rows
      TRIM(t) AS tag
    FROM Posts p,
    LATERAL (
      SELECT value AS t
      FROM (
        -- replace surrounding <> then split on "><"
        SELECT regexp_split_to_table(substr(p.Tags, 2, length(p.Tags) - 2), '><') AS value
      ) s
    ) split
    WHERE p.PostTypeId = 1
  ) x
  GROUP BY tag
),
TopTags AS (
  SELECT TagName, TagCount
  FROM TagUsage
  ORDER BY TagCount DESC
  LIMIT 20
),
RecentCommenters AS (
  SELECT
    c.PostId,
    c.UserId,
    c.Text,
    c.CreationDate,
    u.DisplayName AS CommenterName,
    ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
  FROM Comments c
  LEFT JOIN Users u ON c.UserId = u.Id
  WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
Preferences AS (
  SELECT
    p.PostTypeId,
    CASE WHEN p.PostTypeId = 1 THEN 'Question'
         WHEN p.PostTypeId = 2 THEN 'Answer'
         ELSE 'Other' END AS TypeLabel,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.Tags
  FROM Posts p
),
HistoricalChanges AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Text,
    ph.Comment,
    ph.RevisionGUID
  FROM PostHistory ph
  WHERE ph.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
)
SELECT
  rp.PostId,
  rp.PostTypeId,
  pt.Name AS PostTypeName,
  rp.Title,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.Reputation,
  rp.LastActivityDate,
  rp.ViewCount,
  rp.Score,
  rp.Tags,
  ta.TagName AS TopTag,
  ta.TagCount AS TopTagFreq,
  rc.PostId AS RecentCommentPostId,
  rc.UserId AS RecentCommentUserId,
  rc.CommenterName,
  rc.CreationDate AS CommentDate,
  rc.Text AS RecentCommentText,
  v.BountyAmount,
  v.VoteTypeId,
  v.UserId AS VoterUserId,
  v.CreationDate AS VoteDate,
  u2.DisplayName AS VoterName,
  phh.PostHistoryTypeId AS ChangeTypeId,
  pht.Name AS ChangeTypeName,
  phh.CreationDate AS ChangeDate
FROM RecentActivePosts rp
JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN (
  SELECT TagName, TagCount
  FROM TopTags
) ta ON true
LEFT JOIN RecentCommenters rc ON rc.PostId = rp.PostId AND rc.rn = 1
LEFT JOIN Votes v ON rp.PostId = v.PostId AND v.VoteTypeId IN (2, 3, 8, 9)
LEFT JOIN Users u2 ON v.UserId = u2.Id
LEFT JOIN Badges b ON rp.OwnerUserId = b.UserId AND b.Class = 1
LEFT JOIN PostLinks pl ON rp.PostId = pl.PostId
LEFT JOIN PostHistory phh ON rp.PostId = phh.PostId
LEFT JOIN PostHistoryTypes pht ON phh.PostHistoryTypeId = pht.Id
GROUP BY
  rp.PostId,
  rp.PostTypeId,
  pt.Name,
  rp.Title,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.Reputation,
  rp.LastActivityDate,
  rp.ViewCount,
  rp.Score,
  rp.Tags,
  ta.TagName,
  ta.TagCount,
  rc.PostId,
  rc.UserId,
  rc.CommenterName,
  rc.CreationDate,
  rc.Text,
  v.BountyAmount,
  v.VoteTypeId,
  v.UserId,
  v.CreationDate,
  u2.DisplayName,
  phh.PostHistoryTypeId,
  pht.Name,
  phh.CreationDate
ORDER BY rp.LastActivityDate DESC, rp.Score DESC
LIMIT 100;