WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.CreationDate,
        P.Title,
        U.DisplayName AS OwnerDisplayName,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        COUNT(CASE WHEN C.Id IS NOT NULL THEN 1 END) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS RN
    FROM 
        Posts P
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        P.Id, P.Title, P.CreationDate, U.DisplayName
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        OwnerDisplayName,
        Upvotes,
        Downvotes,
        CommentCount,
        RN
    FROM 
        RankedPosts
    WHERE 
        RN = 1
)
SELECT 
    TP.Title,
    TP.OwnerDisplayName,
    (TP.Upvotes - TP.Downvotes) AS NetVotes,
    TP.CommentCount,
    CASE 
        WHEN TP.Upvotes > 100 THEN 'Hot'
        WHEN TP.Upvotes BETWEEN 50 AND 100 THEN 'Trending'
        ELSE 'Normal'
    END AS Popularity
FROM 
    TopPosts TP
WHERE 
    CommentCount > 5
ORDER BY 
    NetVotes DESC, CommentCount DESC
LIMIT 10;
