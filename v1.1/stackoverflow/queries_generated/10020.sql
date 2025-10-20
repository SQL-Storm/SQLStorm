-- {"query": "10020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 592} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
RecentVotes AS (
    SELECT 
        V.PostId,
        V.UserId,
        V.VoteTypeId,
        V.CreationDate
    FROM 
        Votes V
    WHERE 
        V.CreationDate >= NOW() - INTERVAL '30 days'
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COUNT(DISTINCT RV.UserId) AS RecentVoters,
    MAX(CASE WHEN RV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS HasRecentUpvote,
    MAX(CASE WHEN RV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS HasRecentDownvote,
    SUBSTRING(RP.Title FROM 1 FOR 10) AS ShortTitle,
    U.Reputation,
    U.Location,
    U.AboutMe,
    U.WebsiteUrl
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    RecentVotes RV ON RP.Id = RV.PostId
LEFT JOIN 
    Users U ON RP.OwnerUserId = U.Id
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, BC.BadgeCount, U.Reputation, U.Location, U.AboutMe, U.WebsiteUrl
HAVING 
    COUNT(DISTINCT RV.UserId) > 5
ORDER BY 
    RP.Rank, RP.Score DESC;
