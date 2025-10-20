WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE(u.UpVotes + u.DownVotes, 0) AS TotalVotes,
           NULLIF(u.Location, '') AS CleanLocation
    FROM Users u
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users)
),
UserPosts AS (
    SELECT p.Id AS PostId,
           p.OwnerUserId,
           p.Score,
           p.ViewCount,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
           STRING_AGG(t.TagName, ', ') AS PostTags,
           CASE WHEN p.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS Status,
           p.CreationDate,
           p.ClosedDate
    FROM Posts p
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.ClosedDate
),
AggregatedBadges AS (
    SELECT b.UserId, COUNT(b.Id) AS BadgeCount,
           MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    WHERE b.Class = 1 OR b.TagBased = TRUE
    GROUP BY b.UserId
),
UserActivity AS (
    SELECT tu.Id,
           tu.DisplayName,
           tu.Reputation,
           tu.UserRank,
           COALESCE(up.Score, 0) AS AvgPostScore,
           (SELECT COUNT(c.Id)
            FROM Comments c
            WHERE EXISTS (
                SELECT 1 FROM UserPosts up2 WHERE up2.OwnerUserId = tu.Id AND up2.PostId = c.PostId
            )
              AND c.Score > 0) AS PositiveComments,
           ab.BadgeCount,
           tu.TotalVotes * COALESCE((SELECT AVG(v.VoteTypeId) FROM Votes v WHERE EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = tu.Id AND p2.Id = v.PostId)), 0) AS WeightedVotes
    FROM TopUsers tu
    LEFT JOIN (
        SELECT OwnerUserId, AVG(Score) AS Score
        FROM UserPosts
        GROUP BY OwnerUserId
    ) up ON tu.Id = up.OwnerUserId
    LEFT JOIN AggregatedBadges ab ON tu.Id = ab.UserId
    WHERE tu.CleanLocation IS NOT NULL OR tu.Reputation > 10000
),
PostEdits AS (
    SELECT ph.PostId, COUNT(ph.Id) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
)
SELECT ua.Id,
       ua.DisplayName,
       ua.Reputation,
       ua.UserRank,
       ua.AvgPostScore,
       ua.PositiveComments,
       ua.BadgeCount,
       ua.WeightedVotes,
       COALESCE(ph.EditCount, 0) AS EditCount,
       RANK() OVER (ORDER BY ua.Reputation DESC, COALESCE(ua.BadgeCount,0) DESC) AS OverallRank
FROM UserActivity ua
LEFT JOIN PostEdits ph ON EXISTS (
    SELECT 1 FROM UserPosts up3 WHERE up3.OwnerUserId = ua.Id AND up3.PostId = ph.PostId
)

UNION ALL

SELECT NULL AS Id,
       'Summary' AS DisplayName,
       SUM(s.Reputation) AS Reputation,
       NULL AS UserRank,
       AVG(s.AvgPostScore) AS AvgPostScore,
       SUM(s.PositiveComments) AS PositiveComments,
       SUM(COALESCE(s.BadgeCount,0)) AS BadgeCount,
       SUM(COALESCE(s.WeightedVotes,0)) AS WeightedVotes,
       SUM(COALESCE(s.EditCount,0)) AS EditCount,
       NULL AS OverallRank
FROM (
    SELECT ua.Id,
           ua.DisplayName,
           ua.Reputation,
           ua.UserRank,
           ua.AvgPostScore,
           ua.PositiveComments,
           ua.BadgeCount,
           ua.WeightedVotes,
           COALESCE((
               SELECT SUM(pe.EditCount)
               FROM PostEdits pe
               WHERE EXISTS (SELECT 1 FROM UserPosts up4 WHERE up4.OwnerUserId = ua.Id AND up4.PostId = pe.PostId)
           ), 0) AS EditCount
    FROM UserActivity ua
) s
ORDER BY OverallRank;