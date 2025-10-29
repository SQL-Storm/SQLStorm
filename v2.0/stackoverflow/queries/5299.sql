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
    p.LastActivityDate,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    AVG(v.BountyAmount) AS AvgBounty,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks l ON l.PostId = p.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
  GROUP BY
    p.Id,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    p.Id AS PostId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
UserSummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
  FROM Users u
),
Flagged AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    COUNT(t.Id) AS TotalNotices
  FROM Posts p
  LEFT JOIN PostHistory t ON t.PostId = p.Id
  WHERE t.PostHistoryTypeId IN (33,34) -- Post Notice Added/Removed
  GROUP BY
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate
)
SELECT
  rh.PostId,
  rh.Title,
  rh.Tags AS RawTags,
  rh.CreationDate,
  rh.LastActivityDate,
  rh.Score,
  rh.ViewCount,
  rh.UpVotes,
  rh.DownVotes,
  rh.AvgBounty,
  gs.DisplayName AS OwnerName,
  gs.Reputation,
  gs.BadgeCount,
  u.Id AS OwnerUserId,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rh.PostId) AS CommentCount,
  f.TotalNotices
FROM RecentHot rh
LEFT JOIN Users u ON u.Id = rh.OwnerUserId
LEFT JOIN UserSummary gs ON gs.UserId = u.Id
LEFT JOIN Flagged f ON f.PostId = rh.PostId
WHERE rh.rn <= 50
ORDER BY rh.LastActivityDate DESC, rh.Score DESC, rh.ViewCount DESC;