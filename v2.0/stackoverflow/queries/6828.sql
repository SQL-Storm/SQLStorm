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
        U.Id AS UserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1
        AND P.Score > 0
        AND P.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month')
),
BadgeSummary AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(B.Class) AS BadgePoints
    FROM 
        Badges B
    WHERE 
        B.Date >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    GROUP BY 
        B.UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    RS.TotalBadges,
    RS.BadgePoints,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.UserId END) AS UpVotes,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.UserId END) AS DownVotes,
    COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.UserId END) AS CloseVotes,
    COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0) AS NumberOfCloses,
    CASE 
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeSummary RS ON RP.UserId = RS.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId
GROUP BY 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    RP.UserId,
    RP.Rank,
    RS.TotalBadges,
    RS.BadgePoints
ORDER BY 
    RP.Rank ASC;