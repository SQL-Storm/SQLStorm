-- {"query": "6500.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 493} 

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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.LastActivityDate DESC) AS Rank,
        COALESCE(SUM(V.Score), 0) OVER (PARTITION BY P.Id) AS TotalVotes
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
BadgesSummary AS (
    SELECT 
        B.UserId,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(B.Class) AS BadgeClassTotal
    FROM 
        Badges B
    GROUP BY 
        B.UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.Rank,
    RP.TotalVotes,
    RP.CreationDate,
    RP.LastActivityDate,
    B.TotalBadges,
    B.BadgeClassTotal,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    CASE 
        WHEN RP.ViewCount > 1000 THEN 'Popular'
        ELSE 'Not Popular'
    END AS ViewTier
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgesSummary B ON RP.OwnerDisplayName = B.UserId
WHERE 
    EXISTS (
        SELECT 1 
        FROM PostHistory PH 
        WHERE PH.PostId = RP.Id AND PH.PostHistoryTypeId = 10 AND PH.Comment IN (
            SELECT Name FROM CloseReasonTypes WHERE Id IN (101, 102, 103)
        )
    )
ORDER BY 
    RP.Rank, RP.Score DESC;
