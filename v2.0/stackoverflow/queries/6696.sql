-- {"query": "6696.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 441}
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
    GROUP BY 
        U.Id
)
SELECT 
    R.Id,
    R.Title,
    R.Score,
    R.ViewCount,
    R.CreationDate,
    R.DisplayName,
    R.Reputation,
    R.rank,
    B.BadgeCount,
    CASE 
        WHEN R.rank <= 3 THEN 'Top'
        WHEN R.rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus,
    (
        SELECT 
            STRING_AGG(LT.Name, ', ')
        FROM 
            LinkTypes LT
        JOIN 
            PostLinks PL ON LT.Id = PL.LinkTypeId
        WHERE 
            PL.PostId = R.Id
    ) AS LinkedTypes,
    (
        SELECT 
            COUNT(*)
        FROM 
            Votes V
        WHERE 
            V.PostId = R.Id AND V.VoteTypeId IN (2, 15)
    ) AS PositiveActions
FROM 
    RankedPosts R
LEFT JOIN 
    BadgeCounts B ON R.DisplayName = CAST(B.UserId AS TEXT)
WHERE 
    R.rank <= 10
GROUP BY
    R.Id,
    R.Title,
    R.Score,
    R.ViewCount,
    R.CreationDate,
    R.DisplayName,
    R.Reputation,
    R.rank,
    B.BadgeCount
ORDER BY 
    R.Score DESC, R.ViewCount DESC;