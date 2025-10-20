WITH TopUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        COALESCE(SUM(P.Score), 0) AS TotalScore
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
    ORDER BY 
        TotalScore DESC
    LIMIT 1000
),
ActivePosts AS (
    SELECT
        P.Id,
        P.Title,
        P.ViewCount,
        P.Score,
        P.CreationDate,
        P.OwnerUserId,
        COALESCE(PC.CommentCount, 0) AS CommentCount
    FROM 
        Posts P
    LEFT JOIN 
        (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) PC ON P.Id = PC.PostId
    WHERE
        P.PostTypeId IN (1, 2)
        AND P.Score > 10
),
TopActivePosts AS (
    SELECT 
        AP.Id AS PostId,
        AP.Title,
        AP.OwnerUserId,
        AP.ViewCount,
        AP.Score,
        AP.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY AP.OwnerUserId ORDER BY AP.Score DESC, AP.ViewCount DESC) AS rn
    FROM 
        ActivePosts AP
    JOIN 
        TopUsers TU ON AP.OwnerUserId = TU.UserId
)
SELECT 
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TAP.PostId,
    TAP.Title,
    TAP.Score,
    TAP.ViewCount,
    TAP.CommentCount
FROM
    TopUsers TU
JOIN 
    TopActivePosts TAP ON TU.UserId = TAP.OwnerUserId
WHERE 
    TAP.rn <= 5
GROUP BY
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TAP.PostId,
    TAP.Title,
    TAP.Score,
    TAP.ViewCount,
    TAP.CommentCount,
    TAP.rn
ORDER BY 
    TU.Reputation DESC, TAP.Score DESC, TAP.ViewCount DESC;