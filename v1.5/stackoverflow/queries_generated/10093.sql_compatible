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
        U.Id,
        U.DisplayName,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM 
        Users U
    JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    COALESCE(BC.badge_count, 0) AS badge_count,
    RS.upvotes,
    RS.downvotes,
    U.Reputation,
    U.DisplayName,
    U.Location,
    U.AboutMe,
    U.WebsiteUrl
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.Id = BC.Id
LEFT JOIN 
    VoteSummary RS ON RP.Id = RS.Id
JOIN 
    Users U ON RP.Id = U.Id
WHERE 
    RP.rank <= 10
ORDER BY 
    RP.Score DESC, RP.rank ASC;