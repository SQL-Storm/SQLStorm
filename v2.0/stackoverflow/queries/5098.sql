-- {"query": "5098.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 726}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(p.Tags, '<>')) AS Tag
  FROM Posts p
  WHERE p.Id IN (SELECT Id FROM RecentActivePosts)
),
TagStats AS (
  SELECT
    t.Tag,
    COUNT(*) AS PostCount,
    AVG(rap.Score) AS AvgScore,
    SUM(rap.ViewCount) AS TotalViews
  FROM RecentActivePosts rap
  JOIN LATERAL (
    SELECT unnest(string_to_array(rap.Tags, '<>')) AS Tag
  ) t ON true
  GROUP BY t.Tag
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesGiven,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeActivity AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
PrimaryTags AS (
  SELECT DISTINCT ON (p.Id) p.Id AS PostId, unnest(string_to_array(p.Tags, '<>')) AS Tag
  FROM Posts p
  WHERE p.Id IN (SELECT Id FROM RecentActivePosts)
),
Combined AS (
  SELECT
    rap.Id AS PostId,
    rap.Title,
    rap.CreationDate,
    rap.OwnerUserId,
    rap.Score,
    rap.ViewCount,
    rap.LastActivityDate,
    rap.PostTypeId,
    pt.Tag AS PrimaryTag,
    ts.PostCount,
    ts.AvgScore,
    ts.TotalViews,
    ua.UserId AS ActivityUserId,
    ua.DisplayName AS ActivityUserName,
    ua.Reputation AS ActivityUserRep,
    ba.BadgeCount,
    ba.LastBadgeDate
  FROM RecentActivePosts rap
  LEFT JOIN TagStats ts ON true
  LEFT JOIN PrimaryTags pt ON pt.PostId = rap.Id
  LEFT JOIN Users u ON u.Id = rap.OwnerUserId
  LEFT JOIN UserActivity ua ON ua.UserId = u.Id
  LEFT JOIN BadgeActivity ba ON ba.UserId = u.Id
)
SELECT
  PostId,
  Title,
  CreationDate,
  OwnerUserId,
  Score,
  ViewCount,
  LastActivityDate,
  PostTypeId,
  COALESCE(PrimaryTag, 'untagged') AS TopTag,
  PostCount,
  AvgScore,
  TotalViews,
  ActivityUserName,
  ActivityUserRep,
  BadgeCount,
  LastBadgeDate
FROM Combined
ORDER BY LastActivityDate DESC, Score DESC
LIMIT 200;