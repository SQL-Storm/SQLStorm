-- {"query": "6120.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 566} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation,
        U.Location,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank,
        COUNT(*) OVER (PARTITION BY P.PostTypeId) AS TotalPosts
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS BadgeCount
    FROM 
        Badges
    WHERE 
        Class = 1 AND TagBased = FALSE
    GROUP BY 
        UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    TO_CHAR(RP.CreationDate, 'YYYY-MM-DD') AS CreationDate,
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Location,
    RP.Rank,
    RP.TotalPosts,
    BC.BadgeCount,
    CASE 
        WHEN RP.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'High'
        WHEN RP.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Low'
        ELSE 'Average'
    END AS ScoreTier,
    STRING_AGG(DISTINCT T.TagName, ', ') WITHIN GROUP AS ORDER BY T.TagName ASC AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    UNNEST(STRING_TO_ARRAY(P.Tags, '/><')) AS T(TagName)
LEFT JOIN 
    Tags T ON T.TagName = T.TagName
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.OwnerDisplayName, RP.Reputation, RP.Location, RP.Rank, RP.TotalPosts, BC.BadgeCount
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
