
WITH RECURSIVE UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName
), 
PopularTags AS (
    SELECT 
        SUBSTRING_INDEX(SUBSTRING_INDEX(A.Tags, '><', numbers.n), '><', -1) AS TagName,
        COUNT(*) AS TagCount
    FROM 
        Posts A
    INNER JOIN (
        SELECT 1 as n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 
        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 
        UNION ALL SELECT 9 UNION ALL SELECT 10
    ) numbers ON CHAR_LENGTH(A.Tags) - CHAR_LENGTH(REPLACE(A.Tags, '><', '')) >= numbers.n - 1
    WHERE 
        A.PostTypeId = 1  
    GROUP BY 
        TagName
    HAVING 
        COUNT(*) > 5  
), 
TagStats AS (
    SELECT 
        T.TagName,
        AVG(P.Score) AS AvgScore,
        SUM(P.ViewCount) AS TotalViews,
        COUNT(DISTINCT P.Id) AS QuestionCount
    FROM 
        PopularTags T
    JOIN 
        Posts P ON P.Tags LIKE CONCAT('%<', T.TagName, '>%' )
    GROUP BY 
        T.TagName
)

SELECT 
    UA.DisplayName,
    UA.TotalPosts,
    UA.QuestionCount,
    UA.AnswerCount,
    TS.TagName,
    TS.AvgScore,
    TS.TotalViews
FROM 
    UserActivity UA
LEFT JOIN 
    TagStats TS ON UA.QuestionCount > 0 
ORDER BY 
    UA.TotalPosts DESC, TS.TotalViews DESC
LIMIT 10;
