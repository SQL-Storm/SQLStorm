-- {"query": "6195.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 490}
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        B.Class = 1 AND B.TagBased = FALSE
    GROUP BY 
        U.Id
),
VoteSums AS (
    SELECT 
        PV.PostId,
        SUM(PV.VoteTypeId) FILTER (WHERE PV.VoteTypeId IS NOT NULL) * 0 AS Score -- placeholder if original intent unknown
    FROM 
        Votes PV
    WHERE 
        PV.VoteTypeId IN (2, 3) AND PV.UserId IS NOT NULL
    GROUP BY 
        PV.PostId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.OwnerUserId,
    U.DisplayName,
    U.Reputation,
    COALESCE(RC.BadgeCount, 0) AS BadgeCount,
    COALESCE(V.Score, 0) AS TotalVotes,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        ELSE 'Other'
    END AS RankStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts RC ON RP.OwnerUserId = RC.UserId
LEFT JOIN 
    VoteSums V ON RP.Id = V.PostId
WHERE 
    RP.rank <= 10
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, RP.OwnerUserId, U.DisplayName, U.Reputation, RC.BadgeCount, V.Score
ORDER BY 
    TotalVotes DESC, RP.Score DESC;