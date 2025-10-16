WITH
TopUsers AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         u.Location,
         u.AboutMe
  FROM Users u
  WHERE u.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days'
  ORDER BY u.Reputation DESC
  LIMIT 200
),
RecentPostActivity AS (
  /* Replace COUNT(DISTINCT c.Id) OVER (...) with COUNT(c.Id) OVER (...) and ensure deduplication via aggregation if needed.
     Here we compute comment count per post using window over PostId; PostId is in GROUP BY of the aggregate subquery. */
  SELECT p.Id AS PostId,
         p.PostTypeId,
         p.OwnerUserId,
         p.Title,
         p.Tags,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.LastActivityDate,
         p.AcceptedAnswerId,
         p.ParentId,
         p.CommentCount,
         p.FavoriteCount,
         p.Body,
         p.ContentLicense,
         COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountWindow,
         SUM(CASE WHEN vh.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS CloseVotesWindow
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN PostHistory vh ON vh.PostId = p.Id
  WHERE p.OwnerUserId IN (SELECT UserId FROM TopUsers)
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
Last7DaysActivity AS (
  SELECT rp.PostId,
         rp.PostTypeId,
         rp.OwnerUserId,
         rp.Title,
         rp.Tags,
         rp.CreationDate,
         rp.Score,
         rp.ViewCount,
         rp.LastActivityDate,
         rp.AcceptedAnswerId,
         rp.ParentId,
         rp.CommentCount,
         rp.FavoriteCount,
         rp.Body,
         rp.ContentLicense,
         CASE WHEN rp.ViewCount IS NULL THEN 0 ELSE rp.ViewCount END
           / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - rp.CreationDate)) / 3600.0, 0) AS ViewsPerHour,
         COALESCE(NULLIF(rp.Tags, ''), 'untagged') AS NormalizedTags,
         rp.CommentCountWindow,
         rp.CloseVotesWindow
  FROM RecentPostActivity rp
  WHERE rp.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days'
),
BenchmarkPairs AS (
  SELECT l.Id AS LinkId,
         l.PostId AS FromPost,
         l.RelatedPostId AS ToPost,
         l.LinkTypeId,
         p1.OwnerUserId AS FromUser,
         p2.OwnerUserId AS ToUser,
         p1.Score AS FromScore,
         p2.Score AS ToScore,
         p1.ViewCount AS FromViews,
         p2.ViewCount AS ToViews,
         p1.LastActivityDate AS FromLastActivity,
         p2.LastActivityDate AS ToLastActivity
  FROM PostLinks l
  JOIN Posts p1 ON p1.Id = l.PostId
  JOIN Posts p2 ON p2.Id = l.RelatedPostId
  WHERE l.LinkTypeId IN (1, 3)
    AND p1.OwnerUserId IN (SELECT UserId FROM TopUsers)
    AND p2.OwnerUserId IN (SELECT UserId FROM TopUsers)
),
AuthorPostRank AS (
  SELECT
    bu.UserId,
    bu.DisplayName,
    bu.Reputation,
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY bu.UserId ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.CreationDate DESC) AS RankByScore
  FROM TopUsers bu
  JOIN Last7DaysActivity rp ON rp.OwnerUserId = bu.UserId
),
FinalOutput AS (
  SELECT
    adb.UserId,
    adb.DisplayName,
    adb.Reputation,
    ab.PostId,
    ab.Title,
    ab.CreationDate,
    ab.Score,
    ab.ViewCount,
    ab.LastActivityDate,
    ab.NormalizedTags,
    ab.ViewsPerHour,
    ab.CloseVotesWindow,
    ab.CommentCountWindow,
    apr.RankByScore,
    bb.FromPost,
    bb.ToPost,
    bb.FromScore,
    bb.ToScore,
    bb.FromViews,
    bb.ToViews,
    bb.LinkTypeId
  FROM TopUsers adb
  LEFT JOIN Last7DaysActivity ab ON ab.OwnerUserId = adb.UserId
  LEFT JOIN AuthorPostRank apr ON apr.UserId = adb.UserId AND apr.PostId = ab.PostId
  LEFT JOIN BenchmarkPairs bb ON bb.FromUser = adb.UserId OR bb.ToUser = adb.UserId
)
SELECT *
FROM FinalOutput
ORDER BY Reputation DESC, CreationDate ASC
LIMIT 100;