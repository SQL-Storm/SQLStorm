-- {"query": "6274.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 737}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        CAST(P.CreationDate AS DATE) AS CreationDate,
        CAST(P.LastActivityDate AS DATE) AS LastActivityDate,
        U.DisplayName AS Owner,
        U.Reputation,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId NOT IN (3,4,5)
    GROUP BY 
        P.Id, P.Title, P.Score, P.ViewCount, CAST(P.CreationDate AS DATE), CAST(P.LastActivityDate AS DATE), U.DisplayName, U.Reputation, P.PostTypeId
    HAVING 
        COUNT(DISTINCT V.Id) > 100
),
BadgeStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
CommentStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(C.Id) AS CommentCount,
        MAX(C.Score) AS MaxCommentScore,
        MIN(C.Score) AS MinCommentScore
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
    RP.CreationDate AS CreationDate,
    RP.LastActivityDate AS LastActivityDate,
    RP.Owner AS OwnerDisplayName,
    RP.Reputation,
    RS.BadgeCount,
    RS.GoldBadgeCount,
    RS.SilverBadgeCount,
    RS.BronzeBadgeCount,
    CS.CommentCount,
    CS.MaxCommentScore,
    CS.MinCommentScore,
    CASE
        WHEN RP.Rank <= 3 THEN 'Top'
        WHEN RP.Rank <= 10 THEN 'High'
        ELSE 'Low'
    END AS RankStatus
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeStats RS ON RP.Owner = RS.DisplayName
LEFT JOIN 
    CommentStats CS ON RP.Id = CS.PostId
ORDER BY 
    RP.Rank ASC;