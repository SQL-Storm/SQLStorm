-- {"query": "6403.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 521} 

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
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName,
    U.Reputation,
    U.LastAccessDate,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High Scoring'
        ELSE 'Average'
    END AS ScoreTier,
    STRING_AGG(T.TagName, ', ') WITHIN GROUP AS ORDER BY T.TagName ASC AS TagList
FROM 
    RankedPosts RP
JOIN 
    Users U ON RP.OwnerUserId = U.Id
LEFT JOIN 
    PostTags PT ON RP.Id = PT.PostId
LEFT JOIN 
    Tags T ON PT.TagId = T.Id
JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
WHERE 
    EXISTS (
        SELECT 1 
        FROM Votes V 
        WHERE V.PostId = RP.Id AND V.VoteTypeId = 1
    )
    AND RP.Rank <= 100
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, U.DisplayName, U.Reputation, U.LastAccessDate, BC.BadgeCount
ORDER BY 
    RP.Rank;
