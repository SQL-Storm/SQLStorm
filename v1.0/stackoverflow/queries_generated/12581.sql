-- Performance benchmarking query to analyze posts and their associated data
WITH PostMetrics AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        U.DisplayName AS OwnerDisplayName,
        COUNT(C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId = 1 -- Only include questions
    GROUP BY 
        P.Id, U.DisplayName
)

SELECT 
    PM.PostId,
    PM.Title,
    PM.CreationDate,
    PM.Score,
    PM.ViewCount,
    PM.AnswerCount,
    PM.CommentCount,
    PM.OwnerDisplayName,
    PM.UpvoteCount,
    PM.DownvoteCount,
    (PM.UpvoteCount - PM.DownvoteCount) AS NetVotes
FROM 
    PostMetrics PM
ORDER BY 
    PM.Score DESC
LIMIT 100; -- Limit to top 100 posts based on score
