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
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
TopTags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.Tags IS NOT NULL
),
TagStats AS (
  SELECT
    t.TagName,
    count(*) AS TagPostCount,
    avg(p.Score) AS AvgScore,
    max(p.ViewCount) AS MaxViews
  FROM TopTags t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
ActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl
  FROM Users u
  WHERE u.Reputation > 1000
),
UserBadgeAgg AS (
  SELECT
    ub.UserId,
    count(CASE WHEN ub.Class = 1 THEN 1 END) AS GoldBadges,
    count(CASE WHEN ub.Class = 2 THEN 1 END) AS SilverBadges,
    count(CASE WHEN ub.Class = 3 THEN 1 END) AS BronzeBadges
  FROM Badges ub
  GROUP BY ub.UserId
),
VotesSummary AS (
  SELECT
    v.PostId,
    sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    sum(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts
  FROM Votes v
  GROUP BY v.PostId
)
SELECT
  rh.PostId,
  rh.Title,
  rh.Tags,
  rh.CreationDate,
  rh.Score,
  rh.ViewCount,
  rh.OwnerUserId,
  rh.LastActivityDate,
  au.DisplayName AS OwnerDisplayName,
  au.Reputation,
  uba.GoldBadges,
  uba.SilverBadges,
  uba.BronzeBadges,
  vs.UpVotes,
  vs.DownVotes,
  vs.BountyStarts,
  wt.TagName,
  ts.TagPostCount,
  ts.AvgScore,
  ts.MaxViews
FROM RecentHot rh
LEFT JOIN ActiveUsers au ON rh.OwnerUserId = au.Id
LEFT JOIN Users u ON rh.OwnerUserId = u.Id
LEFT JOIN UserBadgeAgg uba ON rh.OwnerUserId = uba.UserId
LEFT JOIN VotesSummary vs ON rh.PostId = vs.PostId
LEFT JOIN TopTags wt ON wt.PostId = rh.PostId
LEFT JOIN TagStats ts ON ts.TagName = wt.TagName
ORDER BY rh.LastActivityDate DESC
LIMIT 100;