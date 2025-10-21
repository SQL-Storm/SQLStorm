WITH
  UserStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS CreatedOn,
      u.LastAccessDate AS LastActive,
      COUNT(p.Id) AS PostCount,
      COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
      COALESCE(AVG(p.Score), 0) AS AvgScore,
      MAX(p.LastEditDate) AS LastEdit
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
  ),
  UserComments AS (
    SELECT UserId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY UserId
  ),
  UserVotes AS (
    SELECT UserId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Votes
    GROUP BY UserId
  ),
  UserBadges AS (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
  ),
  UserTagCounts AS (
    SELECT p.OwnerUserId AS UserId,
           t.TagName,
           COUNT(*) AS TagCount
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
    GROUP BY p.OwnerUserId, t.TagName
  ),
  UserTagRanks AS (
    SELECT UserId, TagName, TagCount,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC, TagName) AS rn
    FROM UserTagCounts
  ),
  UserTopTags AS (
    SELECT UserId,
           STRING_AGG(TagName, ', ') AS TopTags
    FROM (
      SELECT UserId, TagName
      FROM UserTagRanks
      WHERE rn <= 5
      ORDER BY UserId, rn
    ) s
    GROUP BY UserId
  ),
  TopRep AS (
    SELECT Id AS UserId, DisplayName, Reputation
    FROM Users
    ORDER BY Reputation DESC
    LIMIT 50
  ),
  TopViews AS (
    SELECT u.Id AS UserId, u.DisplayName, COALESCE(SUM(p.ViewCount), 0) AS Views
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
    ORDER BY Views DESC
    LIMIT 50
  ),
  BenchmarkSet AS (
    SELECT tr.UserId, tr.DisplayName, tr.Reputation, NULL AS Views
    FROM TopRep tr
    UNION ALL
    SELECT tv.UserId, tv.DisplayName, NULL AS Reputation, tv.Views
    FROM TopViews tv
  )
SELECT
  bs.UserId,
  bs.DisplayName,
  bs.Reputation,
  bs.Views,
  us.PostCount,
  uc.CommentCount,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  uv.UpVotesGiven,
  uv.DownVotesGiven,
  COALESCE(ut.TopTags, '') AS TopTags,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.UserId = bs.UserId) AS VotesCast
FROM BenchmarkSet bs
LEFT JOIN UserStats us ON us.UserId = bs.UserId
LEFT JOIN UserComments uc ON uc.UserId = bs.UserId
LEFT JOIN UserBadges ub ON ub.UserId = bs.UserId
LEFT JOIN UserVotes uv ON uv.UserId = bs.UserId
LEFT JOIN UserTopTags ut ON ut.UserId = bs.UserId
ORDER BY bs.UserId
LIMIT 100;