WITH RecentActiveUsers AS (
  SELECT DISTINCT U.Id AS UserId, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes
  FROM Users AS U
  JOIN Posts AS P ON U.Id = P.OwnerUserId
  WHERE P.LastActivityDate >= (DATE '2024-10-01' - INTERVAL '30' DAY)
),
TopTags AS (
  SELECT T.TagName, COUNT(*) AS TagCount
  FROM Posts AS P
  JOIN PostHistory AS PH ON P.Id = PH.PostId
  JOIN Tags AS T ON P.Tags LIKE '%' || T.TagName || '%'
  WHERE PH.PostHistoryTypeId = 2
  GROUP BY T.TagName
  ORDER BY TagCount DESC
  LIMIT 10
),
UserBadgeCounts AS (
  SELECT U.Id AS UserId, COUNT(B.Id) AS BadgeCount
  FROM Users AS U
  LEFT JOIN Badges AS B ON U.Id = B.UserId
  GROUP BY U.Id
),
HighReputationUsers AS (
  SELECT U.Id, U.DisplayName, U.Reputation
  FROM Users AS U
  WHERE U.Reputation > (SELECT AVG(Reputation) FROM Users)
)
SELECT
  RAU.DisplayName AS ActiveUserName,
  COALESCE(TT.TagName, 'No Tags') AS TopTag,
  COALESCE(UBC.BadgeCount, 0) AS BadgeCount,
  CASE
    WHEN HRU.Id IS NOT NULL THEN 'High Reputation'
    ELSE 'Normal'
  END AS ReputationStatus,
  DENSE_RANK() OVER (ORDER BY RAU.Reputation DESC) AS ReputationRank
FROM RecentActiveUsers AS RAU
LEFT JOIN (
  SELECT DISTINCT U.Id
  FROM Users AS U
  JOIN Posts AS P ON U.Id = P.OwnerUserId
  JOIN TopTags AS TT ON P.Tags LIKE '%' || TT.TagName || '%'
) AS TT_MATCH ON RAU.UserId = TT_MATCH.Id
LEFT JOIN TopTags AS TT ON TT_MATCH.Id IS NOT NULL AND TT.TagName IS NOT NULL
LEFT JOIN UserBadgeCounts AS UBC ON RAU.UserId = UBC.UserId
LEFT JOIN HighReputationUsers AS HRU ON RAU.UserId = HRU.Id
WHERE RAU.UpVotes > 0
  AND RAU.DownVotes < (RAU.UpVotes * 0.2)
ORDER BY ReputationRank, BadgeCount DESC, ActiveUserName;