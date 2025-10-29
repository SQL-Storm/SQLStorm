-- {"query": "6432.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 589} 

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
), 
CommentMetrics AS (
    SELECT 
        PC.PostId,
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
    RP.Title AS PostTitle,
    RP.Score AS PostScore,
    RP.ViewCount AS PostViewCount,
    RP.CreationDate AS PostDate,
    RP.rank AS PostRank,
    COALESCE(B.BadgeCount, 0) AS BadgeCount,
    CM.CommentCount AS CommentCount,
    CM.MaxCommentScore AS MaxCommentScore,
    CM.MinCommentScore AS MinCommentScore,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        ELSE 'Low'
    END AS ScoreTier,
    STRING_AGG(T.TagName, ', ') WITHIN GROUP AS ORDER BY T.Count DESC AS TagList
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts B ON RP.UserId = B.UserId
LEFT JOIN 
    CommentMetrics CM ON RP.Id = CM.PostId
LEFT JOIN 
    Posts P ON RP.Id = P.Id
LEFT JOIN 
    Tags T ON P.Id = ANY(STRING_TO_ARRAY(T.Tags, '<', '>')::int[])
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.rank, B.BadgeCount, CM.CommentCount, CM.MaxCommentScore, CM.MinCommentScore
ORDER BY 
    RP.rank, RP.Score DESC, RP.ViewCount DESC;
