-- {"query": "13040.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 661} 

WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostsCount,
        SUM(CASE WHEN P.Score > 10 THEN 1 ELSE 0 END) AS HighScorePosts,
        SUM(P.ViewCount) AS TotalViewCount,
        ROW_NUMBER() OVER (ORDER BY SUM(P.ViewCount) DESC) AS ViewRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1
    WHERE 
        U.Reputation > 1000 AND U.LastAccessDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        U.Id, U.DisplayName
),
EditorStats AS (
    SELECT 
        PH.UserId,
        COUNT(*) AS EditsMade,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (5, 8) THEN LENGTH(PH.Text) ELSE 0 END) AS TotalEditLength
    FROM 
        PostHistory PH
    WHERE 
        PH.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY 
        PH.UserId
),
TopTags AS (
    SELECT
        T.TagName,
        COUNT(DISTINCT P.Id) AS QuestionCount,
        AVG(P.Score) AS AvgScore,
        LAG(AVG(P.Score), 1, 0) OVER (ORDER BY COUNT(DISTINCT P.Id) DESC) AS PrevAvgScore
    FROM 
        Tags T
    INNER JOIN 
        Posts P ON P.Tags LIKE '%<' || T.TagName || '>%' AND P.PostTypeId = 1
    GROUP BY 
        T.TagName
    HAVING 
        COUNT(DISTINCT P.Id) > 50
)
SELECT
    UA.UserId,
    UA.DisplayName,
    UA.PostsCount,
    UA.HighScorePosts,
    UA.TotalViewCount,
    UA.ViewRank,
    COALESCE(ES.EditsMade, 0) AS EditsMade,
    COALESCE(ES.TotalEditLength, 0) AS TotalEditLength,
    TT.TagName,
    TT.QuestionCount,
    TT.AvgScore,
    TT.PrevAvgScore
FROM 
    UserActivity UA
LEFT JOIN 
    EditorStats ES ON UA.UserId = ES.UserId
OUTER APPLY (
    SELECT TOP 3 *
    FROM 
        TopTags
    WHERE 
        AvgScore > 10
    ORDER BY 
        QuestionCount DESC
) TT
WHERE 
    UA.ViewRank <= 100
ORDER BY 
    UA.TotalViewCount DESC, TT.QuestionCount DESC;
