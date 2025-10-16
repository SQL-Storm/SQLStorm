WITH UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        MAX(P.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC) AS PostRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        U.Reputation > 1000
        AND P.CreationDate >= DATE '2022-01-01'
    GROUP BY 
        U.Id, U.DisplayName
),
TopQuestions AS (
    SELECT 
        P.Id,
        P.Title,
        P.ViewCount,
        P.Score,
        COALESCE(U.DisplayName, 'Anonymous') AS Author,
        P.OwnerUserId,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS QuestionRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1
        AND P.Score > 10
)
SELECT
    UA.Id,
    UA.DisplayName,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalUpvotes,
    UA.TotalDownvotes,
    UA.LastPostDate,
    TQ.Title AS TopQuestion,
    TQ.ViewCount AS TopQuestionViews,
    TQ.Score AS TopQuestionScore
FROM 
    UserActivity UA
LEFT JOIN 
    TopQuestions TQ ON UA.Id = TQ.OwnerUserId
WHERE 
    UA.PostRank <= 100
    AND (TQ.QuestionRank = 1 OR TQ.QuestionRank IS NULL)
GROUP BY
    UA.Id,
    UA.DisplayName,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalUpvotes,
    UA.TotalDownvotes,
    UA.LastPostDate,
    UA.PostRank,
    TQ.Title,
    TQ.ViewCount,
    TQ.Score,
    TQ.QuestionRank,
    TQ.OwnerUserId
ORDER BY 
    UA.TotalPosts DESC,
    TQ.Score DESC;