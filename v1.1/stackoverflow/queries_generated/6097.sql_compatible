WITH
RecentlyActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerDisplayName,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag,
    p.Id AS PostId
  FROM RecentlyActivePosts p
  WHERE p.Tags IS NOT NULL
),
TagStats AS (
  SELECT
    tt.tag AS TagName,
    COUNT(*) AS PostCount,
    AVG(rp.Score) AS AvgScore,
    MAX(rp.ViewCount) AS MaxViews
  FROM TopTags tt
  JOIN RecentlyActivePosts rp ON rp.Id = tt.PostId
  GROUP BY tt.tag
),
UserImpact AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(DISTINCT v.Id) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId IN (2,8,9,10,11) THEN 1 ELSE 0 END) AS NegativeVotes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
ActivityScore AS (
  SELECT
    up.UserId,
    up.DisplayName,
    up.Reputation,
    up.VoteCount,
    up.NegativeVotes,
    COUNT(DISTINCT rp.Id) AS PostsCreatedRecently,
    SUM(p.Score) AS NetPostScore
  FROM UserImpact up
  LEFT JOIN Posts p ON p.OwnerUserId = up.UserId
  LEFT JOIN Posts rp ON rp.Id = p.Id
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  GROUP BY up.UserId, up.DisplayName, up.Reputation, up.VoteCount, up.NegativeVotes
),
Composite AS (
  SELECT
    a.UserId,
    a.DisplayName,
    a.Reputation,
    a.VoteCount,
    a.NegativeVotes,
    a.PostsCreatedRecently,
    a.NetPostScore,
    (a.Reputation * 0.5 + a.VoteCount * 2 - a.NegativeVotes) AS EngagementScore
  FROM ActivityScore a
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.VoteCount,
  c.NegativeVotes,
  c.PostsCreatedRecently,
  c.NetPostScore,
  c.EngagementScore,
  tt.TagName,
  tt.PostCount AS TagPostCount,
  tt.AvgScore AS TagAvgScore,
  tt.MaxViews AS TagMaxViews
FROM Composite c
LEFT JOIN (
  SELECT
    t.TagName,
    SUM(t.PostCount) OVER () AS TotalPosts,
    t.PostCount,
    t.AvgScore,
    t.MaxViews
  FROM TagStats t
) tt ON true
ORDER BY c.EngagementScore DESC, c.Reputation DESC
LIMIT 100;