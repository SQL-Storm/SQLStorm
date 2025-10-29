-- {"query": "6277.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 480}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        P.OwnerUserId AS UserId,
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
PostBounties AS (
    SELECT 
        PostId, 
        SUM(COALESCE(BountyAmount, 0)) AS BountyAmount
    FROM 
        Votes
    WHERE 
        VoteTypeId = 8
    GROUP BY 
        PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.rank,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > 100 AND RP.ViewCount > 1000 THEN 'High Impact'
        WHEN RP.Score > 50 AND RP.ViewCount > 500 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS ImpactLevel,
    COALESCE(SUM(PB.BountyAmount), 0) AS TotalBounty
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.UserId = BC.UserId
LEFT JOIN 
    PostBounties PB ON RP.Id = PB.PostId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.DisplayName, RP.Reputation, RP.rank, RP.UserId, BC.BadgeCount
ORDER BY 
    RP.rank, RP.Score DESC
LIMIT 100;