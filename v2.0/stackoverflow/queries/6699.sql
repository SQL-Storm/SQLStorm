WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        PC.Id AS PostId, 
        COUNT(C.Id) AS CommentCount
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
    GROUP BY 
        PC.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    COALESCE(CS.CommentCount, 0) AS CommentCount,
    RC.BadgeCount,
    CASE 
        WHEN RP.rank <= 10 THEN 'Top'
        WHEN RP.rank <= 100 THEN 'Mid'
        ELSE 'Bottom'
    END AS RankTier,
    -- Standard SQL way to get the first keyword from the title: use combination of SUBSTRING and POSITION for portability
    CASE
        WHEN POSITION(' ' IN RP.Title) = 0 THEN RP.Title
        ELSE
            CASE
                WHEN POSITION(' ' IN SUBSTRING(RP.Title FROM POSITION(' ' IN RP.Title)+1)) = 0
                THEN SUBSTRING(RP.Title FROM 1 FOR POSITION(' ' IN RP.Title)-1)
                ELSE SUBSTRING(RP.Title FROM 1 FOR POSITION(' ' IN RP.Title)-1)
            END
    END AS FirstKeyword
FROM 
    RankedPosts RP
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerUserId = RC.UserId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    CS.CommentCount,
    RC.BadgeCount
ORDER BY 
    RP.rank, RP.Score DESC
FETCH FIRST 1000 ROWS ONLY;