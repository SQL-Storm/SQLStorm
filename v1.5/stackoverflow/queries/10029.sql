WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.Rank,
    RP.DisplayName AS DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    RC.BadgeCount,
    CASE
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Regular'
    END AS Status,
    STRING_AGG(T.TagName, ', ' ORDER BY T.TagName) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.Id = U.Id
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 1
LEFT JOIN 
    Tags T ON PH.Text = T.TagName
LEFT JOIN 
    BadgeCounts RC ON RP.Id = RC.UserId
WHERE 
    RP.Rank <= 5
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.Rank, RP.DisplayName, RP.Reputation, RP.LastAccessDate, RC.BadgeCount
ORDER BY 
    RP.Rank, RP.Score DESC;