WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId, 
        P.Title, 
        P.Score, 
        P.CreationDate, 
        P.OwnerUserId,
        U.DisplayName AS OwnerName, 
        COUNT(C.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    WHERE 
        P.PostTypeId = 1 AND 
        P.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    GROUP BY 
        P.Id, P.Title, P.Score, P.CreationDate, P.OwnerUserId, U.DisplayName
),
TopPosts AS (
    SELECT 
        PostId, Title, Score, CreationDate, OwnerUserId, OwnerName, CommentCount
    FROM 
        RankedPosts
    WHERE 
        PostRank <= 5
)
SELECT 
    T.OwnerName, 
    COUNT(*) AS TotalTopPosts, 
    AVG(T.Score) AS AverageScore,
    SUM(T.CommentCount) AS TotalComments
FROM 
    TopPosts T
JOIN 
    Users U ON T.OwnerUserId = U.Id
WHERE 
    U.Reputation > 1000
GROUP BY 
    T.OwnerName
ORDER BY 
    TotalTopPosts DESC, AverageScore DESC;