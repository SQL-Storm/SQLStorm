-- {"query": "13066.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 741} 

WITH UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswers,
        AVG(P.Score) AS AvgScore,
        MAX(P.CreationDate) AS LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) DESC, COUNT(DISTINCT P.Id) DESC) AS Rnk
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId IN (1, 2)
    WHERE 
        U.Reputation > 1000 AND U.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY 
        U.Id, U.DisplayName
),
HighQualityPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.OwnerUserId,
        P.Score,
        P.Tags,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS QualityRank
    FROM 
        Posts P
    WHERE 
        P.Score > 25 AND P.AnswerCount > 2
),
TopTags AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostsCount
    FROM 
        Tags T
    JOIN 
        Posts P ON P.Tags LIKE CONCAT('%<', T.TagName, '>%')
    WHERE 
        P.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
    GROUP BY 
        T.TagName
    HAVING 
        COUNT(P.Id) > 100
)
SELECT 
    UA.DisplayName,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.AcceptedAnswers,
    ROUND(UA.AvgScore, 2) AS AvgScore,
    H.Title AS HighestScoringPost,
    TT.TagName AS MostUsedTag
FROM 
    UserActivity UA
LEFT JOIN 
    HighQualityPosts H ON UA.Id = H.OwnerUserId AND H.QualityRank = 1
LEFT JOIN LATERAL (
    SELECT 
        T.TagName
    FROM 
        TopTags T
    JOIN 
        Posts P ON P.Tags LIKE CONCAT('%<', T.TagName, '>%')
    WHERE 
        P.OwnerUserId = UA.Id
    ORDER BY 
        COUNT(P.Id) DESC
    LIMIT 1
) TT ON TRUE
WHERE 
    UA.Rnk <= 100
ORDER BY 
    UA.AcceptedAnswers DESC, UA.TotalPosts DESC;
