WITH ActiveUsers AS (
    SELECT 
        U.Id, 
        U.DisplayName, 
        U.Reputation, 
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT B.Id) AS BadgeCount,
        AVG(P.Score) AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS UserRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1
    LEFT JOIN Badges B ON U.Id = B.UserId AND B.Class = 1
    WHERE U.Reputation > 100000
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
PostStats AS (
    SELECT 
        P.Id AS PostId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate,
        P.ViewCount,
        P.AnswerCount,
        (LENGTH(P.Tags) - LENGTH(REPLACE(P.Tags, '><', '')) + 1) AS TagCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT PH.Id) AS EditHistoryCount
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (4,5,6)
    WHERE P.CreationDate >= '2015-01-01'
    GROUP BY P.Id, P.OwnerUserId, P.Title, P.CreationDate, P.ViewCount, P.AnswerCount, P.Tags
)
SELECT 
    AU.Id AS UserId,
    AU.DisplayName,
    AU.Reputation,
    AU.PostCount,
    AU.BadgeCount,
    AU.AvgPostScore,
    PS.PostId,
    PS.Title,
    PS.CreationDate,
    PS.ViewCount,
    PS.AnswerCount,
    PS.TagCount,
    PS.Upvotes,
    PS.Downvotes,
    PS.CommentCount,
    PS.EditHistoryCount,
    DENSE_RANK() OVER (ORDER BY PS.Upvotes DESC, PS.ViewCount DESC) AS PostRank
FROM ActiveUsers AU
JOIN PostStats PS ON AU.Id = PS.OwnerUserId
WHERE PS.Upvotes > 100 AND PS.AnswerCount > 5
ORDER BY AU.UserRank ASC, PostRank ASC
LIMIT 500;