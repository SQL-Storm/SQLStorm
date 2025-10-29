WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_author,
    COUNT(*) OVER () AS total_rows
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
ExpandedAuthors AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.Tags,
    ra.PostTypeId,
    ra.AcceptedAnswerId,
    ra.ParentId,
    ra.Body,
    ra.ContentLicense,
    ra.rn_by_author,
    ra.total_rows,
    CASE
      WHEN u.Reputation IS NULL THEN 0
      ELSE u.Reputation
    END AS ComputedReputation
  FROM RecentActivity ra
  LEFT JOIN Users u ON ra.OwnerUserId = u.Id
),
TagStats AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    ra.UserId,
    ra.UserName,
    ra.Reputation,
    ra.UserCreationDate,
    ra.LastAccessDate,
    ra.Views,
    ra.UpVotes,
    ra.DownVotes,
    ra.Location,
    ra.WebsiteUrl,
    ra.AboutMe,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.Tags,
    ra.PostTypeId,
    ra.AcceptedAnswerId,
    ra.ParentId,
    ra.Body,
    ra.ContentLicense,
    ra.rn_by_author,
    ra.total_rows,
    ra.ComputedReputation,
    t.TagName AS PrimaryTag,
    COUNT(*) OVER (PARTITION BY ra.OwnerUserId) AS PostsByAuthor
  FROM ExpandedAuthors ra
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(ra.Tags, 2, length(ra.Tags)-2), '><')) AS TagName
  ) t ON TRUE
),
CrossJoin AS (
  SELECT
    wa.PostId,
    wa.Title,
    wa.UserId,
    wa.UserName,
    wa.Reputation,
    wa.LastActivityDate,
    wa.Score,
    wa.ViewCount,
    wa.PrimaryTag,
    wa.PostTypeId,
    wa.AcceptedAnswerId,
    wa.ParentId,
    wa.Body,
    wa.ContentLicense,
    wa.rn_by_author,
    wa.ComputedReputation,
    wa.total_rows,
    wa.PostsByAuthor,
    CASE
      WHEN wa.total_rows > 0 THEN wa.total_rows
      ELSE 0
    END AS TotalPostsInWindow
  FROM TagStats wa
  ORDER BY wa.LastActivityDate DESC
  LIMIT 500
)
SELECT
  PostId,
  Title,
  UserId,
  UserName,
  Reputation,
  LastActivityDate,
  Score,
  ViewCount,
  PrimaryTag,
  PostTypeId,
  AcceptedAnswerId,
  ParentId,
  Body,
  ContentLicense,
  rn_by_author,
  ComputedReputation,
  TotalPostsInWindow
FROM CrossJoin
WHERE PostTypeId = 1
  AND (Score > 0 OR ViewCount > 100)
  AND (PrimaryTag IS NOT NULL)
ORDER BY LastActivityDate DESC, Score DESC, ViewCount DESC;