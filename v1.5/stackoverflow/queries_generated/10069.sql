-- {"query": "10069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 552} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
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
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    U.DisplayName,
    U.Reputation,
    B.BadgeCount,
    CASE 
        WHEN RP.rank <= 3 THEN 'Top'
        WHEN RP.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    SUBSTRING_INDEX(SUBSTRING_INDEX(RP.Title, ' ', -2), ' ', 1) AS FirstKeyword,
    SUBSTRING_INDEX(SUBSTRING_INDEX(RP.Title, ' ', -1), ' ', -1) AS LastKeyword,
    CASE 
        WHEN U.Reputation >= 10000 THEN 'Veteran'
        ELSE 'Newbie'
    END AS UserStatus,
    LAG(RP.Score) OVER (ORDER BY RP.rank) AS PreviousScore,
    LEAD(RP.Score) OVER (ORDER BY RP.rank) AS NextScore,
    COALESCE(SUM(V.BountyAmount) OVER (PARTITION BY RP.Id ORDER BY V.CreationDate), 0) AS TotalBounty
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    BadgeCounts B ON RP.OwnerUserId = B.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId AND V.VoteTypeId = 8
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.rank;
