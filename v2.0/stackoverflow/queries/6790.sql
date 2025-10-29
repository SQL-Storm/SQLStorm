WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
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
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName,
    U.Reputation,
    U.LastAccessDate,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > (SELECT AVG(P2.Score) FROM Posts P2 WHERE P2.PostTypeId = 1) THEN 'High Scoring'
        ELSE 'Average'
    END AS ScoreTier,
    STRING_AGG(T.TagName, ', ' ORDER BY T.TagName) AS TagList
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 10
LEFT JOIN 
    CloseReasonTypes CRT ON PH.Comment = CAST(CRT.Id AS VARCHAR)
LEFT JOIN 
    Tags T ON POSITION(CONCAT('<', T.TagName, '>') IN RP.Title) > 0
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
GROUP BY 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    U.LastAccessDate,
    BC.BadgeCount
HAVING 
    BC.BadgeCount > (SELECT AVG(BadgeCount) FROM BadgeCounts)
ORDER BY 
    RP.Rank;