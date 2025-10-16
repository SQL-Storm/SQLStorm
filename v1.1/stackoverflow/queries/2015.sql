WITH ActiveUsers AS (
    SELECT U.Id AS UserId, U.DisplayName, COUNT(P.Id) AS PostCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.CreationDate > DATE '2021-01-01'
    GROUP BY U.Id, U.DisplayName
    HAVING COUNT(P.Id) > 10
),
RecentBadges AS (
    SELECT B.UserId, COUNT(B.Id) AS BadgeCount
    FROM Badges B
    WHERE B.Date > DATE '2023-01-01'
    GROUP BY B.UserId
),
UserPosts AS (
    SELECT P.OwnerUserId, P.PostTypeId, P.Score, P.Title, P.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS rn
    FROM Posts P
    WHERE P.CreationDate > (
        SELECT MAX(CreationDate) - INTERVAL '1 year' FROM Posts
    )
),
TopRatedPosts AS (
    SELECT OwnerUserId AS UserId, MAX(Score) AS MaxScore
    FROM UserPosts
    GROUP BY OwnerUserId
)
SELECT
    AU.DisplayName,
    AU.PostCount,
    COALESCE(RB.BadgeCount, 0) AS RecentBadges,
    COUNT(DISTINCT C.PostId) AS CommentedPosts
FROM ActiveUsers AU
LEFT JOIN RecentBadges RB ON AU.UserId = RB.UserId
INNER JOIN UserPosts UP ON AU.UserId = UP.OwnerUserId AND UP.rn = 1
INNER JOIN Comments C ON UP.OwnerUserId = C.UserId
INNER JOIN TopRatedPosts TRP ON UP.OwnerUserId = TRP.UserId AND UP.Score = TRP.MaxScore
WHERE UP.PostTypeId IN (1, 2)
  AND C.CreationDate > UP.CreationDate
GROUP BY AU.DisplayName, AU.PostCount, RB.BadgeCount, AU.UserId
HAVING COUNT(DISTINCT C.PostId) > 5
ORDER BY RecentBadges DESC, PostCount DESC, AU.DisplayName ASC;