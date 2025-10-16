-- {"query": "1060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 434} 

WITH UserPostStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN 1 END) AS TotalQuestions,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN 1 END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalScore
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName
),
TopTags AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount
    FROM 
        Tags T
    JOIN 
        Posts P ON T.Id = ANY(string_to_array(P.Tags, '><')::int[])
    GROUP BY 
        T.TagName
    HAVING 
        COUNT(P.Id) > 10
),
CombinedStats AS (
    SELECT 
        UPS.UserId,
        UPS.DisplayName,
        UPS.TotalPosts,
        UPS.TotalQuestions,
        UPS.TotalAnswers,
        UPS.TotalScore,
        TT.TagName,
        ROW_NUMBER() OVER (PARTITION BY UPS.UserId ORDER BY UPS.TotalScore DESC) AS TagRank
    FROM 
        UserPostStats UPS
    LEFT JOIN 
        TopTags TT ON TT.TagName = ANY(string_to_array((SELECT STRING_AGG(P.Tags, ',') FROM Posts P WHERE P.OwnerUserId = UPS.UserId), ','))
)
SELECT 
    C.UserId,
    C.DisplayName,
    COALESCE(C.TotalPosts, 0) AS TotalPosts,
    COALESCE(C.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(C.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(C.TotalScore, 0) AS TotalScore,
    C.TagName,
    C.TagRank
FROM 
    CombinedStats C
WHERE 
    C.TagRank = 1
ORDER BY 
    C.TotalScore DESC, C.DisplayName;
