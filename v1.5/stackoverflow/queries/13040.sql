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
        U.Reputation > 1000 AND U.LastAccessDate > CAST('2024-10-01' AS date) - INTERVAL '1 year'
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
        PH.CreationDate > CAST('2024-10-01' AS date) - INTERVAL '6 months'
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
        Posts P ON P.Tags LIKE CONCAT('%<', T.TagName, '>%') AND P.PostTypeId = 1
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
JOIN (
    SELECT *
    FROM (
        SELECT *
        FROM TopTags
        WHERE AvgScore > 10
        ORDER BY QuestionCount DESC
        LIMIT 3
    ) AS ttt
) AS TT ON 1 = 1
WHERE 
    UA.ViewRank <= 100
ORDER BY 
    UA.TotalViewCount DESC, TT.QuestionCount DESC;