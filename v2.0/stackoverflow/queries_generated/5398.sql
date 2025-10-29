-- {"query": "5398.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 718} 
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
    p.PostId,
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  FROM Posts p
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
    ta.TagName,
    ta.TagName AS TagOnly
  FROM RecentQuestions rq
  LEFT JOIN TaggedMentions ta ON rq.PostId = ta.PostId
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
    coalesce( (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 8), 0 ) AS AvgBounty,
    coalesce( (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 2), 0 ) AS UpModCount,
    coalesce( (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 3), 0 ) AS DownModCount
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
  AND m.rn IS NULL
ORDER BY m.Score DESC, m.ViewCount DESC
LIMIT 100;