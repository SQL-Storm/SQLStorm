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
        U.Id
), 
PopularTags AS (
    SELECT 
        UNNEST(STRING_TO_ARRAY(A.Tags, '><')) AS TagName,
        COUNT(*) AS TagCount
    FROM 
        Posts A
    WHERE 
        A.PostTypeId = 1  -- Only consider Questions
    GROUP BY 
        TagName
    HAVING 
        COUNT(*) > 5  -- At least 5 questions
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

-- Extra code to benchmark forks with comment activity
SELECT 
    C.UserDisplayName,
    COUNT(DISTINCT C.Id) AS CommentCount,
    SUM(CASE WHEN C.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments
FROM 
    Comments C
JOIN 
    PostHistory PH ON C.PostId = PH.PostId
GROUP BY 
    C.UserDisplayName
HAVING 
    COUNT(DISTINCT C.Id) > 10;
