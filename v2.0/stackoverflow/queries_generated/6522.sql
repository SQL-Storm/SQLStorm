-- {"query": "6522.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 447} 

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
    TO_CHAR(RP.CreationDate, 'YYYY-MM-DD') AS CreationDate,
    TO_CHAR(RP.LastActivityDate, 'YYYY-MM-DD') AS LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Rank,
    RP.AnswerCount,
    RP.CommentCount,
    BS.TotalBadges,
    BS.BadgePoints,
    BS.LatestBadgeDate,
    CASE 
        WHEN BS.TotalBadges > 0 THEN 'Active'
        ELSE 'Inactive'
    END AS BadgeStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeSummary BS ON RP.OwnerUserId = BS.UserId
WHERE 
    RP.Rank <= 10
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;
