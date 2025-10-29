WITH
RecentHighImpactPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.Score * 2 + p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substring(r.Tags, 2, length(r.Tags) - 2), '> <')) AS TagName
  FROM RecentHighImpactPosts r
),
TagStats AS (
  SELECT
    tt.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    SUM(CASE WHEN p.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS AnonymousOwners
  FROM TopTags tt
  JOIN Posts p ON p.Tags LIKE '%' || replace(tt.TagName, '''', '''''') || '%'
  GROUP BY tt.TagName
),
EliteUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.LastAccessDate
  FROM Users u
  WHERE u.Reputation > 10000
    AND u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    v.VoteTypeId,
    v.UserId AS VoterId,
    v.CreationDate AS VoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
CrossLink AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1, 3)
),
DistinctPosts AS (
  SELECT DISTINCT
    rp.PostId
  FROM RecentActivity rp
  UNION
  SELECT DISTINCT
    pl.PostId
  FROM CrossLink pl
),
TopTagRanks AS (
  SELECT
    tt.TagName,
    ROW_NUMBER() OVER (PARTITION BY tt.TagName ORDER BY COUNT(*) DESC) AS rn
  FROM TopTags tt
  JOIN Posts p ON p.Tags LIKE '%' || tt.TagName || '%'
  GROUP BY tt.TagName
)
SELECT
  rp.PostId,
  rp.Title AS PostTitle,
  rp.CreationDate AS PostCreated,
  rp.OwnerUserId,
  tr.TagName AS TopTag,
  ts.QuestionCount,
  ts.AvgScore,
  ts.MaxViews,
  owner.Reputation AS OwnerReputation,
  owner.DisplayName AS OwnerDisplayName,
  owner.LastAccessDate AS LastActive
FROM RecentHighImpactPosts rp
LEFT JOIN TopTagRanks tr ON TRUE
LEFT JOIN TagStats ts ON ts.TagName = tr.TagName
LEFT JOIN EliteUsers eu ON eu.Id = rp.OwnerUserId
LEFT JOIN Users owner ON owner.Id = rp.OwnerUserId
LEFT JOIN (
  SELECT u.Id, u.DisplayName, u.Reputation
  FROM Users u
) ev ON ev.Id = rp.OwnerUserId
WHERE rp.rn = 1
ORDER BY rp.CreationDate DESC
LIMIT 100;