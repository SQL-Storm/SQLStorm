WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        U.DisplayName AS Author,
        P.CreationDate,
        P.ViewCount,
        P.Score,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS PostRank,
        COUNT(CASE WHEN C.Id IS NOT NULL THEN 1 END) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.CreationDate >= (DATE '2024-10-01' - INTERVAL '30' DAY)
    GROUP BY 
        P.Id, P.Title, U.DisplayName, P.CreationDate, P.ViewCount, P.Score, P.OwnerUserId
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        Author,
        ViewCount,
        Score,
        CommentCount,
        UpVoteCount,
        DownVoteCount,
        CASE 
            WHEN PostRank = 1 THEN 'Latest Post'
            ELSE 'Other Posts'
        END AS PostType
    FROM 
        RankedPosts
)
SELECT 
    PostId,
    Title,
    Author,
    ViewCount,
    Score,
    CommentCount,
    UpVoteCount,
    DownVoteCount,
    PostType
FROM 
    TopPosts
ORDER BY 
    ViewCount DESC, Score DESC
LIMIT 10;