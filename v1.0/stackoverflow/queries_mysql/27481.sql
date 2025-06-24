
WITH TagCounts AS (
    SELECT 
        SUBSTRING_INDEX(SUBSTRING_INDEX(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><', numbers.n), '><', -1) AS TagName,
        COUNT(*) AS PostCount
    FROM 
        Posts
        JOIN (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 
              UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) numbers
        ON CHAR_LENGTH(Tags) - CHAR_LENGTH(REPLACE(Tags, '><', '')) >= numbers.n - 1
    WHERE 
        PostTypeId = 1  
    GROUP BY 
        TagName
),
TopTags AS (
    SELECT 
        TagName,
        PostCount,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC) AS TagRank
    FROM 
        TagCounts
    WHERE 
        PostCount > 1  
),
UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS NetScore,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS AnswerCount
    FROM 
        Users U
    JOIN 
        Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 2  
    LEFT JOIN 
        Votes V ON V.PostId = P.Id
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
ActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        NetScore,
        AnswerCount,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, NetScore DESC) AS UserRank
    FROM 
        UserReputation
    WHERE 
        Reputation > 1000  
)
SELECT 
    T.TagName,
    T.PostCount,
    U.DisplayName AS TopUserDisplayName,
    U.Reputation AS TopUserReputation,
    U.NetScore AS TopUserNetScore
FROM 
    TopTags T
JOIN 
    Posts P ON P.Tags LIKE CONCAT('%', T.TagName, '%')  
JOIN 
    ActiveUsers U ON P.OwnerUserId = U.UserId
WHERE 
    U.UserRank <= 5  
ORDER BY 
    T.PostCount DESC, U.NetScore DESC;
