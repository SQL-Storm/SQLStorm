-- {"query": "6477.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 716} 

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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount,
        MAX(CASE WHEN B.Class = 1 THEN B.Date ELSE NULL END) AS GoldBadgeDate,
        MAX(CASE WHEN B.Class = 2 THEN B.Date ELSE NULL END) AS SilverBadgeDate,
        MAX(CASE WHEN B.Class = 3 THEN B.Date ELSE NULL END) AS BronzeBadgeDate
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
    RP.LastActivityDate,
    RP.OwnerDisplayName,
    RP.Reputation,
    RP.Location,
    BC.BadgeCount,
    BC.GoldBadgeDate,
    BC.SilverBadgeDate,
    BC.BronzeBadgeDate,
    SUM(V.Score) AS TotalVotes,
    AVG(EXTRACT(EPOCH FROM V.CreationDate - RP.CreationDate) / 3600.0) AS AvgHourlyVoteRate,
    CASE 
        WHEN RP.Score > 1000 THEN 'High'
        WHEN RP.Score BETWEEN 100 AND 1000 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    STRING_AGG(DISTINCT T.TagName, ', ') WITHIN GROUP (ORDER BY T.TagName) AS Tags
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeCounts BC ON RP.OwnerUserId = BC.UserId
LEFT JOIN 
    Votes V ON RP.Id = V.PostId
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId AND PH.PostHistoryTypeId = 10
LEFT JOIN 
    Tags T ON FIND_IN_SET(T.Id, RP.Tags) > 0
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate,
    RP.OwnerDisplayName, RP.Reputation, RP.Location, BC.BadgeCount, BC.GoldBadgeDate,
    BC.SilverBadgeDate, BC.BronzeBadgeDate
HAVING 
    AVG(EXTRACT(EPOCH FROM V.CreationDate - RP.CreationDate) / 3600.0) > 0.5
ORDER BY 
    TotalVotes DESC, RP.Score DESC;
