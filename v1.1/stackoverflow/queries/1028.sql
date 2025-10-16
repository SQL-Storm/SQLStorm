WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE U.Reputation > 1000
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.ViewCount,
        COALESCE(A.Id, -1) AS AcceptedAnswer,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS RecentPostRank
    FROM Posts P
    LEFT JOIN Posts A ON P.AcceptedAnswerId = A.Id
    WHERE P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
TopPosts AS (
    SELECT 
        P.OwnerUserId AS UserId,
        P.Title,
        P.ViewCount,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.ViewCount DESC) AS ViewRank
    FROM PostDetails P
),
FinalResults AS (
    SELECT 
        UA.UserId,
        UA.DisplayName,
        UA.Reputation,
        UA.PostCount,
        UA.CommentCount,
        UA.UpVotes,
        UA.DownVotes,
        COALESCE(TP.Title, 'No Posts') AS TopPostTitle,
        COALESCE(TP.ViewCount, 0) AS TopPostViewCount,
        TP.ViewRank
    FROM UserActivity UA
    LEFT JOIN TopPosts TP ON UA.UserId = TP.UserId AND TP.ViewRank = 1
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    CommentCount,
    UpVotes,
    DownVotes,
    TopPostTitle,
    TopPostViewCount
FROM FinalResults
WHERE Reputation > 0
ORDER BY Reputation DESC, PostCount DESC
LIMIT 10;