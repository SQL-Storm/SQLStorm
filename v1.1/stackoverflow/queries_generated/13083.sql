-- {"query": "13083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 685} 

WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(U.Reputation) AS MaxReputation,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id
),
PostPerformance AS (
    SELECT 
        P.Id AS PostId,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS PostRank
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.ClosedDate IS NULL
),
TopQuestions AS (
    SELECT 
        P.PostId,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        U.DisplayName,
        EXTRACT(YEAR FROM P.CreationDate) AS YearCreated,
        DENSE_RANK() OVER (ORDER BY P.Score DESC, P.FavoriteCount DESC) AS Rank
    FROM PostPerformance P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostRank <= 5
),
CommentAggregates AS (
    SELECT 
        PostId,
        COUNT(*) AS TotalComments,
        SUM(LENGTH(Text)) AS TotalCommentLength
    FROM Comments
    GROUP BY PostId
)
SELECT 
    TQ.PostId,
    TQ.Score,
    TQ.ViewCount,
    TQ.AnswerCount,
    TQ.FavoriteCount,
    TQ.DisplayName,
    TQ.YearCreated,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.MaxReputation,
    UA.TotalBadges,
    UA.GoldBadges,
    COALESCE(CA.TotalComments, 0) AS TotalComments,
    COALESCE(CA.TotalCommentLength, 0) AS TotalCommentLength,
    RANK() OVER (PARTITION BY TQ.YearCreated ORDER BY TQ.Score DESC, TQ.FavoriteCount DESC) AS YearlyRank
FROM TopQuestions TQ
JOIN UserActivity UA ON TQ.DisplayName = UA.UserId
LEFT JOIN CommentAggregates CA ON TQ.PostId = CA.PostId
WHERE TQ.Rank <= 100
ORDER BY TQ.YearCreated DESC, TQ.Score DESC;
