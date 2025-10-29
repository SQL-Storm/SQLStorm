-- {"query": "6204.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 569} 

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
        U.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
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
    RP.CreationDate AS PostDate,
    RP.LastActivityDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.UserId END) OVER (PARTITION BY RP.Id) AS UpvoteCount,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.UserId END) OVER (PARTITION BY RP.Id) AS DownvoteCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High Scoring'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium Scoring'
        ELSE 'Low Scoring'
    END AS ScoreTier,
    STRING_AGG(T.TagName, ', ') WITHIN GROUP (ORDER BY T.Count DESC) AS TopTags
FROM 
    RankedPosts RP
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
LEFT JOIN 
    Tags T ON RP.Id = T.ExcerptPostId
LEFT JOIN 
    BadgeCounts BC ON RP.DisplayName = BC.UserId
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.DisplayName, RP.Reputation, RP.LastAccessDate, BC.BadgeCount
HAVING 
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.UserId END) > 5
ORDER BY 
    RP.Rank;
