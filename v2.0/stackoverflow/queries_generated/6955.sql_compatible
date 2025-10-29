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
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS rank
    FROM 
        Posts P
        JOIN Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1 AND P.Score > 0 AND P.ViewCount > 100
),
BadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Users U
        JOIN Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
VoteSummary AS (
    SELECT 
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Votes V
    GROUP BY 
        V.PostId
),
AvgBadge AS (
    SELECT AVG(BadgeCount) AS AvgBadgeCount FROM BadgeCounts
)
SELECT 
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
    RP.rank,
    VS.UpVotes,
    VS.DownVotes,
    AB.AvgBadgeCount
FROM 
    RankedPosts RP
    LEFT JOIN VoteSummary VS ON RP.Id = VS.PostId
    CROSS JOIN AvgBadge AB
WHERE 
    RP.rank <= 10
    AND RP.Reputation > 1000
    AND RP.Location IS NOT NULL
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
    RP.rank,
    VS.UpVotes,
    VS.DownVotes,
    AB.AvgBadgeCount
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;