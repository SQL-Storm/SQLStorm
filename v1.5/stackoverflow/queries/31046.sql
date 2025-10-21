WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        U.DisplayName AS OwnerDisplayName,
        COUNT(CASE WHEN C.Id IS NOT NULL THEN 1 END) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    WHERE 
        P.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY 
        P.Id, P.Title, P.CreationDate, P.Score, P.ViewCount, U.DisplayName, P.OwnerUserId
),
TopRankedPosts AS (
    SELECT 
        Id, Title, CreationDate, Score, ViewCount, OwnerDisplayName
    FROM 
        RankedPosts
    WHERE 
        Rank <= 3
)
SELECT 
    TRP.Title,
    TRP.OwnerDisplayName,
    TRP.Score,
    TRP.ViewCount,
    COUNT(B.Id) AS BadgeCount,
    SUM(COALESCE(V.BountyAmount, 0)) AS TotalBounty
FROM 
    TopRankedPosts TRP
LEFT JOIN 
    Badges B ON TRP.OwnerDisplayName = (SELECT DisplayName FROM Users WHERE Id = B.UserId)
LEFT JOIN 
    Votes V ON TRP.Id = V.PostId AND V.VoteTypeId = 8
GROUP BY 
    TRP.Title, TRP.OwnerDisplayName, TRP.Score, TRP.ViewCount
ORDER BY 
    TRP.Score DESC, TotalBounty DESC
LIMIT 10;