-- {"query": "10070.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 701} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.LastActivityDate,
        U.DisplayName AS Owner,
        U.Reputation,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id, P.Title, P.Score, P.ViewCount, P.CreationDate, P.LastActivityDate, U.DisplayName, U.Reputation
),
BadgeStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount,
        SUM(B.Class) AS BadgeClassTotal
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
    RP.Rank,
    RP.Owner AS OwnerDisplayName,
    RP.Reputation,
    RS.BadgeCount,
    RS.BadgeClassTotal,
    SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY RP.Id) AS ClosedCount,
    CASE 
        WHEN RP.Score > 100 THEN 'High'
        WHEN RP.Score BETWEEN 50 AND 100 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreTier,
    SUBSTRING(RP.Title FROM 1 FOR 30) AS ShortTitle
FROM 
    RankedPosts RP
LEFT JOIN 
    BadgeStats RS ON RP.Owner = RS.DisplayName
LEFT JOIN 
    PostHistory PH ON RP.Id = PH.PostId
WHERE 
    RP.Rank <= 10
    AND (RP.Score > 0 OR RP.ViewCount > 100)
    AND (SELECT COUNT(*) FROM Votes WHERE PostId = RP.Id AND VoteTypeId = 2) > 
        (SELECT COUNT(*) FROM Votes WHERE PostId = RP.Id AND VoteTypeId = 3)
GROUP BY 
    RP.Id, RP.Title, RP.Score, RP.ViewCount, RP.CreationDate, RP.LastActivityDate, RP.Rank, RP.Owner, RP.Reputation, RS.BadgeCount, RS.BadgeClassTotal
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
