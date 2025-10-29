WITH
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
    MAX(p.CreationDate) AS LastPostDate,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE u.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserBadges AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.TagBased = TRUE) AS TagBadges,
    COUNT(*) FILTER (WHERE b.TagBased = FALSE) AS NamedBadges,
    STRING_AGG(b.Name, ',') AS BadgeNames
  FROM Badges b
  GROUP BY b.UserId
),
PostHistoryStats AS (
  SELECT
    p.OwnerUserId AS UserId,
    ph.PostHistoryTypeId,
    COUNT(*) AS TypeCount
  FROM PostHistory ph
  JOIN Posts p ON p.Id = ph.PostId
  WHERE ph.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
  GROUP BY p.OwnerUserId, ph.PostHistoryTypeId
),
TopRelated AS (
  SELECT
    t.TagName,
    COUNT(*) AS RelatedCount
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
  GROUP BY t.TagName
  ORDER BY RelatedCount DESC
  LIMIT 10
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  COALESCE(ub.TagBadges, 0) AS TagBadges,
  COALESCE(ub.NamedBadges, 0) AS NamedBadges,
  ub.BadgeNames,
  ua.PostCount,
  ua.UpvotesReceived,
  ua.DownvotesReceived,
  ua.LastPostDate,
  ua.LastVoteDate,
  pld.TotalPostLikes,
  phs1.TypeCount AS HistType1,
  phs2.TypeCount AS HistType2,
  phs3.TypeCount AS HistType3,
  tr.TagName AS TopTag,
  tr.RelatedCount AS TopRelatedCount
FROM UserActivity ua
LEFT JOIN UserBadges ub ON ub.UserId = ua.UserId
LEFT JOIN (
  SELECT
    p.OwnerUserId AS UserId,
    SUM(COALESCE(v.BountyAmount, 0)) AS TotalPostLikes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  GROUP BY p.OwnerUserId
) pld ON pld.UserId = ua.UserId
LEFT JOIN PostHistoryStats phs1 ON phs1.UserId = ua.UserId AND phs1.PostHistoryTypeId = 1
LEFT JOIN PostHistoryStats phs2 ON phs2.UserId = ua.UserId AND phs2.PostHistoryTypeId = 2
LEFT JOIN PostHistoryStats phs3 ON phs3.UserId = ua.UserId AND phs3.PostHistoryTypeId = 3
LEFT JOIN TopRelated tr ON 1=1
ORDER BY ua.Reputation DESC, ua.PostCount DESC
LIMIT 100;