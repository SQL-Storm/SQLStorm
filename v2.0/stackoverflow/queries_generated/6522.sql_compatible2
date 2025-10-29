WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        P.AnswerCount,
        P.CommentCount,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeSummary AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(B.Class) AS BadgePoints,
        MAX(B.Date) AS LatestBadgeDate
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
    CAST(RP.CreationDate AS DATE) AS CreationDate,
    CAST(RP.LastActivityDate AS DATE) AS LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Rank,
    RP.AnswerCount,
    RP.CommentCount,
    BS.TotalBadges,
    BS.BadgePoints,
    BS.LatestBadgeDate,
    CASE 
        WHEN COALESCE(BS.TotalBadges, 0) > 0 THEN 'Active'
        ELSE 'Inactive'
    END AS BadgeStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeSummary BS ON RP.OwnerUserId = BS.UserId
WHERE 
    RP.Rank <= 10
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    CAST(RP.CreationDate AS DATE),
    CAST(RP.LastActivityDate AS DATE),
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Rank,
    RP.AnswerCount,
    RP.CommentCount,
    BS.TotalBadges,
    BS.BadgePoints,
    BS.LatestBadgeDate
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;