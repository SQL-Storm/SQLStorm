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
        B.Class = 1 AND B.Date >= DATE '2022-01-01'
    GROUP BY 
        U.Id
),
CommentMetrics AS (
    SELECT 
        PC.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore
    FROM 
        Posts PC
    LEFT JOIN 
        Comments C ON PC.Id = C.PostId
    GROUP BY 
        PC.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.rank,
    RP.DisplayName,
    RP.Reputation,
    BC.BadgeCount,
    CM.CommentCount,
    CM.MaxCommentScore,
    CM.MinCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score > 0 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    STRING_AGG(tg.TagName, ', ' ORDER BY tg.TagName) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.DisplayName = (SELECT U2.DisplayName FROM Users U2 WHERE U2.Id = BC.UserId)
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN LATERAL (
    -- Split XML/HTML-like tag string in P.Tags (e.g. "<tag1><tag2>") into rows
    -- Adapt to dialect: use regexp_split_to_table for Postgres-like, fallback to generic approach with VALUES if unavailable.
    SELECT TRIM(both '<>' FROM part) AS TagName
    FROM (VALUES (P.Tags)) AS v(tags)
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(v.tags, '><') AS part
    ) s
) AS tg ON TRUE
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, RP.DisplayName, RP.Reputation, BC.BadgeCount, CM.CommentCount, CM.MaxCommentScore, CM.MinCommentScore
ORDER BY 
    ScoreTier DESC, RP.rank ASC;