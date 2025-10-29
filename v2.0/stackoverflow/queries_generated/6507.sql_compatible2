WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
VoteCounts AS (
    SELECT
        V.PostId,
        COUNT(V.Id) AS VoteCount,
        COUNT(DISTINCT V.UserId) AS DistinctVoters -- non-windowed distinct count per post
    FROM
        Votes V
    GROUP BY
        V.PostId
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
    BC.BadgeCount,
    CASE 
        WHEN COALESCE(VC.DistinctVoters, 0) > 5 THEN 'HighlyActive'
        ELSE 'LowActive'
    END AS ActivityLevel,
    STRING_AGG(T.TagName, ', ' ORDER BY T.TagName) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 1
LEFT JOIN 
    Tags T ON RP.Id = T.ExcerptPostId
LEFT JOIN 
    VoteCounts VC ON RP.Id = VC.PostId
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    RP.Rank <= 10
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, RP.OwnerUserId, U.DisplayName, U.Reputation, BC.BadgeCount, VC.DistinctVoters
ORDER BY 
    RP.Rank, RP.Score DESC;