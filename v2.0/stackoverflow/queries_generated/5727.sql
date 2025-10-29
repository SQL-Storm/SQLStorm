-- {"query": "5727.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 676} 
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
  WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
),
ExpandedAuthors AS (
  SELECT
    ra.PostId,
    ra.Title,
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate,
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
    CASE
      WHEN u.Reputation IS NULL THEN 0
      ELSE u.Reputation
    END AS ComputedReputation
  FROM RecentActivity ra
  LEFT JOIN Users u ON ra.OwnerUserId = u.Id
),
TagStats AS (
  SELECT
    ra.*,
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
    CASE
      WHEN wa.TotalRows > 0 THEN wa.TotalRows
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
ORDER BY LastActivityDate DESC, Score DESC, ViewCount DESC
;