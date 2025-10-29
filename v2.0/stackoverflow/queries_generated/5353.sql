-- {"query": "5353.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 751} 
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
    AND p.CreationDate >= current_timestamp - interval '90 days'
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
    count(*) FILTER (WHERE ub.Class = 1) AS GoldBadges,
    count(*) FILTER (WHERE ub.Class = 2) AS SilverBadges,
    count(*) FILTER (WHERE ub.Class = 3) AS BronzeBadges
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
  rh.Id AS PostId,
  rh.Title,
  rh.Tags,
  rh.CreationDate,
  rh.Score,
  rh.ViewCount,
  rh.OwnerUserId,
  rh.LastActivityDate,
  ha.DisplayName AS OwnerDisplayName,
  uu.Reputation,
  aa.GoldBadges,
  aa.SilverBadges,
  aa.BronzeBadges,
  vs.UpVotes,
  vs.DownVotes,
  vs.BountyStarts,
  wt.TagName,
  ts.TagPostCount,
  ts.AvgScore,
  ts.MaxViews
FROM RecentHot rh
LEFT JOIN ActiveUsers au ON rh.OwnerUserId = au.Id
LEFT JOIN Users aa_user ON rh.OwnerUserId = aa_user.Id
LEFT JOIN UserBadgeAgg aa ON rh.OwnerUserId = aa.UserId
LEFT JOIN ActiveUsers au2 ON rh.OwnerUserId = au2.Id
LEFT JOIN UserBadgeAgg aa ON rh.OwnerUserId = aa.UserId
LEFT JOIN VotesSummary vs ON rh.Id = vs.PostId
LEFT JOIN TopTags wt ON wt.PostId = rh.Id
LEFT JOIN TagStats ts ON ts.TagName = wt.TagName
ORDER BY rh.LastActivityDate DESC
LIMIT 100;