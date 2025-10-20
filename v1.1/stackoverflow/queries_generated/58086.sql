-- {"query": "58086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1060} 

WITH ActiveUsers AS (
    SELECT 
        U.Id, U.Reputation, U.DisplayName, 
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT B.Id) AS GoldBadgeCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId AND V.VoteTypeId = 2
    LEFT JOIN Badges B ON U.Id = B.UserId AND B.Class = 1
    WHERE U.Reputation > 10000
    GROUP BY U.Id, U.Reputation, U.DisplayName
    HAVING COUNT(DISTINCT P.Id) > 50 AND COUNT(DISTINCT C.Id) > 100 AND COUNT(DISTINCT B.Id) > 5
),
PostStats AS (
    SELECT 
        OwnerUserId,
        AVG(AnswerCount) AS AvgAnswerCount,
        MAX(FavoriteCount) AS MaxFavoriteCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ViewCount) AS MedianViews
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
)
SELECT 
    AU.Id,
    AU.DisplayName,
    AU.Reputation,
    AU.PostCount,
    AU.CommentCount,
    AU.GoldBadgeCount,
    AU.TotalUpvotes,
    PS.AvgAnswerCount,
    PS.MaxFavoriteCount,
    PS.MedianViews,
    RANK() OVER (ORDER BY AU.Reputation DESC) AS GlobalRank,
    DENSE_RANK() OVER (PARTITION BY AU.GoldBadgeCount / 5 ORDER BY PS.AvgAnswerCount DESC) AS AnswerQualityRank
FROM ActiveUsers AU
JOIN PostStats PS ON AU.Id = PS.OwnerUserId
WHERE PS.MedianViews > 1000
ORDER BY AU.Reputation DESC, AnswerQualityRank
LIMIT 100;
