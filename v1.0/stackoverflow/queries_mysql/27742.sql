
WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN P.ViewCount > 100 THEN 1 ELSE 0 END) AS PopularPosts,
        SUM(CASE WHEN P.Score < 0 THEN 1 ELSE 0 END) AS NegativeFeedback
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName
),
PopularTags AS (
    SELECT 
        TRIM(BOTH '<>' FROM SUBSTRING_INDEX(SUBSTRING_INDEX(P.Tags, '><', numbers.n), '><', -1)) AS TagName,
        COUNT(P.Id) AS TagUsageCount
    FROM 
        Posts P
    JOIN 
        (SELECT 1 n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 
         UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) numbers
    ON CHAR_LENGTH(P.Tags) - CHAR_LENGTH(REPLACE(P.Tags, '><', '')) >= numbers.n - 1
    WHERE 
        P.PostTypeId = 1 
    GROUP BY 
        TagName
),
ActiveUsers AS (
    SELECT 
        UA.UserId,
        UA.DisplayName,
        UA.TotalPosts,
        UA.QuestionCount,
        UA.AnswerCount,
        UA.PopularPosts,
        UA.NegativeFeedback,
        PT.TagName,
        PT.TagUsageCount
    FROM 
        UserActivity UA
    JOIN 
        PopularTags PT 
    ON 
        UA.QuestionCount > 0
    ORDER BY 
        UA.TotalPosts DESC, PT.TagUsageCount DESC
    LIMIT 10
)
SELECT 
    AU.DisplayName,
    AU.TotalPosts,
    AU.QuestionCount,
    AU.AnswerCount,
    AU.PopularPosts,
    AU.NegativeFeedback,
    AU.TagName,
    AU.TagUsageCount
FROM 
    ActiveUsers AU
ORDER BY 
    AU.PopularPosts DESC, AU.TagUsageCount DESC;
