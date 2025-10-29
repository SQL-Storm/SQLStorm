-- {"query": "6888.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 465}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
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
        U.Id,
        U.DisplayName,
        COUNT(B.Id) AS badge_count
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
VoteSummary AS (
    SELECT 
        V.PostId,
        SUM(V.BountyAmount) AS total_bounty
    FROM 
        Votes V
    WHERE 
        V.VoteTypeId = 8
    GROUP BY 
        V.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    COALESCE(RS.total_bounty, 0) AS total_bounty,
    U.Reputation,
    U.DisplayName,
    BC.badge_count,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS rank_category
FROM 
    RankedPosts RP
LEFT JOIN 
    VoteSummary RS ON RP.Id = RS.PostId
JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts BC ON U.Id = BC.Id
WHERE 
    RP.rank <= 10 AND U.Reputation > 100
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RS.total_bounty,
    U.Reputation,
    U.DisplayName,
    BC.badge_count
ORDER BY 
    RP.rank, RP.Score DESC;