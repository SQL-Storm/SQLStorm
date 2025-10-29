-- {"query": "6444.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 494} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank_score,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.Score DESC) AS rank_views
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.ViewCount > 0
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(DISTINCT Id) AS badge_count
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    BC.badge_count,
    CASE 
        WHEN RP.rank_score <= 3 THEN 'Top Score'
        WHEN RP.rank_views <= 3 THEN 'Top Views'
        ELSE 'Regular'
    END AS rank,
    STRING_AGG(T.TagName, ', ') WITHIN GROUP AS ORDER BY T.Count DESC AS tag_list
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    UNNEST(STRING_TO_ARRAY(P.Tags, '/><')) AS tag ON VALUE AS T.TagName
WHERE 
    RP.PostTypeId = 1
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.DisplayName, RP.Reputation, BC.badge_count
HAVING 
    COUNT(T.TagName) > 2
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;
