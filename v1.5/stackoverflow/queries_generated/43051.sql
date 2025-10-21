-- {"query": "43051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 525} 

WITH UserActivity AS (
    SELECT 
        U.Id, 
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(P.Score) AS MaxPostScore,
        AVG(P.Score) AS AvgPostScore,
        AVG(U.Reputation) AS AvgReputation
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
TopPerformers AS (
    SELECT 
        UA.Id,
        UA.DisplayName,
        UA.TotalPosts,
        UA.TotalBadges,
        UA.TotalQuestions,
        UA.TotalAnswers,
        UA.MaxPostScore,
        UA.AvgPostScore,
        UA.AvgReputation,
        ROW_NUMBER() OVER (ORDER BY UA.TotalPosts DESC, UA.AvgReputation DESC) AS Rank
    FROM 
        UserActivity UA
)
SELECT 
    TP.DisplayName,
    TP.TotalPosts,
    TP.TotalBadges,
    TP.TotalQuestions,
    TP.TotalAnswers,
    TP.MaxPostScore,
    ROUND(TP.AvgPostScore, 2) AS AvgPostScore,
    ROUND(TP.AvgReputation, 2) AS AvgReputation,
    (SELECT COUNT(*) FROM Comments C WHERE C.UserId = TP.Id) AS TotalComments,
    (SELECT COUNT(*) FROM Votes V WHERE V.UserId = TP.Id AND V.VoteTypeId = 2) AS TotalUpvotes,
    (SELECT COUNT(*) FROM PostHistory PH WHERE PH.UserId = TP.Id AND PH.PostHistoryTypeId = 5) AS TotalEdits
FROM 
    TopPerformers TP
WHERE 
    TP.Rank <= 10
ORDER BY 
    TP.Rank;
