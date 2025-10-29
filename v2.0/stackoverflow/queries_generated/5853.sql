-- {"query": "5853.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 715} 
WITH
EligiblePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.Body,
    p.CreationDate,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.LastEditDate,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
CorrelatedTagStats AS (
  SELECT
    ep.PostId,
    ep.Title,
    unnest(string_to_array(substr(ep.Tags, 2, length(ep.Tags)-2), '><')) AS TagName,
    ep.Score,
    ep.ViewCount,
    ep.FavoriteCount,
    ep.OwnerUserId,
    ep.Reputation,
    ep.OwnerDisplayName,
    ep.CreationDate AS PostCreationDate,
    ep.LastActivityDate,
    ep.ParentId,
    ep.AcceptedAnswerId,
    ep.ContentLicense
  FROM EligiblePosts ep
  CROSS JOIN LATERAL unnest(string_to_array(substr(ep.Tags, 2, length(ep.Tags)-2), '><')) AS t(TagName)
),
TopTagsAgg AS (
  SELECT
    TagName,
    COUNT(*) AS PostCount,
    AVG(Score) AS AvgScore,
    SUM(ViewCount) AS TotalViews
  FROM CorrelatedTagStats
  GROUP BY TagName
),
RecentActivity AS (
  SELECT
    ep.PostId,
    ep.OwnerUserId,
    ep.Title,
    ep.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY ep.OwnerUserId ORDER BY ep.LastActivityDate DESC) AS rn
  FROM EligiblePosts ep
),
WindowedOwners AS (
  SELECT
    ra.OwnerUserId,
    ra.Title,
    ra.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY ra.OwnerUserId ORDER BY ra.LastActivityDate DESC) AS seq
  FROM RecentActivity ra
  WHERE ra.LastActivityDate > now() - interval '180 days'
)
SELECT
  tp.TagName,
  tp.PostCount,
  tp.AvgScore,
  tp.TotalViews,
  wu.OwnerUserId,
  wu.Title AS LatestPostTitle,
  wu.LastActivityDate AS LatestPostDate,
  u.DisplayName AS LatestPostOwner,
  u.Reputation AS LatestOwnerReputation,
  u.Views AS LatestOwnerViews
FROM TopTagsAgg tp
LEFT JOIN (
  SELECT
    wa.OwnerUserId,
    wa.Title,
    wa.LastActivityDate
  FROM WindowedOwners wa
  JOIN Users u ON wa.OwnerUserId = u.Id
  WHERE wa.seq = 1
) wu ON TRUE
LEFT JOIN Users u ON wu.OwnerUserId = u.Id
ORDER BY tp.TotalViews DESC, tp.PostCount DESC
LIMIT 200;