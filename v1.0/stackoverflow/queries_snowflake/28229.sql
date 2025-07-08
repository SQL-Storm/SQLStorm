
WITH TagCounts AS (
    SELECT 
        TRIM(LEADING '<' FROM TRIM(TRAILING '>' FROM TAG)) AS Tag,
        COUNT(*) AS PostCount
    FROM 
        Posts
    WHERE 
        PostTypeId = 1  
        AND Tags IS NOT NULL
    GROUP BY 
        TRIM(LEADING '<' FROM TRIM(TRAILING '>' FROM TAG))
),
TopTags AS (
    SELECT 
        Tag, 
        PostCount,
        RANK() OVER (ORDER BY PostCount DESC) AS TagRank
    FROM 
        TagCounts
    WHERE 
        PostCount > 10  
),
UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS QuestionCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1  
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    GROUP BY 
        U.Id, U.DisplayName
),
MostActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        QuestionCount,
        UpvoteCount,
        DownvoteCount,
        RANK() OVER (ORDER BY QuestionCount DESC) AS UserRank
    FROM 
        UserActivity
    WHERE 
        QuestionCount > 5  
)
SELECT 
    T.Tag,
    T.PostCount,
    U.DisplayName,
    U.QuestionCount,
    U.UpvoteCount,
    U.DownvoteCount 
FROM 
    TopTags T
JOIN 
    MostActiveUsers U ON T.Tag IN (
        SELECT TRIM(LEADING '<' FROM TRIM(TRAILING '>' FROM TAG))
        FROM Posts 
        WHERE OwnerUserId = U.UserId AND PostTypeId = 1
        AND Tags IS NOT NULL
    )
ORDER BY 
    T.PostCount DESC, U.QuestionCount DESC;
