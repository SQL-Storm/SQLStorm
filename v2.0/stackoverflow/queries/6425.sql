-- {"query": "6425.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 511}
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
        U.Location,
        U.AboutMe,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        P.OwnerUserId,
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
        B.UserId,
        COUNT(B.Id) AS BadgeCount,
        MAX(CASE WHEN B.TagBased THEN 'Tag' ELSE 'Named' END) AS BadgeType
    FROM 
        Badges B
    GROUP BY 
        B.UserId
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS HighestCommentScore
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id AS PostId,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.DisplayName,
    RP.Reputation,
    RP.Location,
    RP.AboutMe,
    RP.Views,
    RP.UpVotes,
    RP.DownVotes,
    COALESCE(BC.BadgeCount, 0) AS BadgeCount,
    BC.BadgeType,
    CSS.CommentCount,
    CSS.HighestCommentScore,
    ROW_NUMBER() OVER (ORDER BY RP.Score DESC, RP.ViewCount DESC) AS GlobalRank
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    CommentStats CSS ON RP.Id = CSS.PostId
GROUP BY
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.LastActivityDate,
    RP.DisplayName,
    RP.Reputation,
    RP.Location,
    RP.AboutMe,
    RP.Views,
    RP.UpVotes,
    RP.DownVotes,
    RP.OwnerUserId,
    BC.BadgeCount,
    BC.BadgeType,
    CSS.CommentCount,
    CSS.HighestCommentScore
ORDER BY 
    GlobalRank;