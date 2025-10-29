-- {"query": "6006.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 674}
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        U.Id AS UserId,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank,
        CASE 
            WHEN P.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = P.Id AND Posts.PostTypeId = 2)
            ELSE 0
        END AS AnswerCount
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
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
)
SELECT 
    RP.Id,
    RP.Title,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.DisplayName,
    RP.Reputation,
    RP.LastAccessDate,
    RP.Rank,
    RP.AnswerCount,
    BS.BadgeCount,
    BS.GoldBadgeCount,
    BS.SilverBadgeCount,
    BS.BronzeBadgeCount,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId IN (2, 15) THEN V.UserId END) AS UpvoteCount,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId IN (3, 15) THEN V.UserId END) AS DownvoteCount,
    MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END) AS CloseReason,
    MAX(CASE WHEN PH.PostHistoryTypeId = 8 THEN PH.Comment END) AS ReopenReason
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeStats BS ON RP.UserId = BS.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId
WHERE 
    RP.Rank <= 10
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.DisplayName, RP.Reputation, RP.LastAccessDate, RP.Rank, RP.AnswerCount, RP.UserId,
    BS.BadgeCount, BS.GoldBadgeCount, BS.SilverBadgeCount, BS.BronzeBadgeCount
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC
LIMIT 100;