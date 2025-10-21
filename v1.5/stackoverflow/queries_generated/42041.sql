-- {"query": "42041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 564} 

WITH RECURSIVE UserPostCounts AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        COUNT(P.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(P.Id) DESC) AS Rank
    FROM 
        Users U
    JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        U.Id, U.DisplayName
), TagPostCounts AS (
    SELECT 
        T.TagName, 
        COUNT(P.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(P.Id) DESC) AS Rank
    FROM 
        Tags T
    JOIN 
        Posts P ON T.Id = ANY(string_to_array(P.Tags, '><'))
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        T.TagName
), PostActivity AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        COUNT(C.Id) AS CommentCount,
        COUNT(V.Id) AS VoteCount
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id, P.Title, P.CreationDate, P.LastActivityDate, U.DisplayName
)
SELECT 
    UPC.UserId, 
    UPC.DisplayName, 
    UPC.PostCount, 
    TPC.TagName, 
    TPC.PostCount AS TagPostCount, 
    PA.PostId, 
    PA.Title, 
    PA.CreationDate, 
    PA.LastActivityDate, 
    PA.OwnerDisplayName, 
    PA.CommentCount, 
    PA.VoteCount
FROM 
    UserPostCounts UPC
JOIN 
    TagPostCounts TPC ON UPC.Rank = TPC.Rank
JOIN 
    PostActivity PA ON UPC.UserId = PA.OwnerUserId
WHERE 
    UPC.Rank <= 10
ORDER BY 
    UPC.PostCount DESC, 
    TPC.PostCount DESC, 
    PA.LastActivityDate DESC;
