-- {"query": "6804.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 498}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
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
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id
),
TagCounts AS (
    SELECT
        T.ExcerptPostId AS PostId,
        T.TagName,
        COUNT(*) AS Count
    FROM Tags T
    GROUP BY T.ExcerptPostId, T.TagName
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.Rank,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    RC.BadgeCount,
    CASE 
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankCategory,
    STRING_AGG(TC.TagName, ', ' ORDER BY TC.Count DESC) AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    Users U ON RP.OwnerDisplayName = U.DisplayName
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 10
LEFT JOIN 
    TagCounts TC ON RP.Id = TC.PostId
LEFT JOIN 
    BadgeCounts RC ON U.Id = RC.UserId
WHERE 
    (PH.Comment IS NULL OR PH.Comment NOT LIKE '%Duplicate%')
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, U.DisplayName, U.Reputation, RC.BadgeCount
ORDER BY 
    RP.Rank ASC;