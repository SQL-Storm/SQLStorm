WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        U.DisplayName AS Author,
        P.CreationDate,
        P.ViewCount,
        P.Score,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS PostRank,
        COUNT(C.Id) AS CommentCount,
        SUM(CASE WHEN V.Id IS NOT NULL AND V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.Id IS NOT NULL AND V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
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