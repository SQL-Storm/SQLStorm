WITH RecentPosts AS (
    SELECT 
        P.Id,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        COALESCE(U.DisplayName, 'Community User') AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS PostRank,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) AS DownVoteCount
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY 
        P.Id, U.DisplayName
),

PostWithBadges AS (
    SELECT 
        RP.Id,
        RP.Title,
        RP.CreationDate,
        RP.Score,
        RP.ViewCount,
        RP.OwnerDisplayName,
        RP.UpVoteCount,
        RP.DownVoteCount,
        COUNT(B.Id) AS BadgeCount
    FROM 
        RecentPosts RP
    LEFT JOIN 
        Badges B ON RP.OwnerDisplayName = (SELECT DisplayName FROM Users WHERE Id = B.UserId)
    GROUP BY 
        RP.Id
),

RankedPosts AS (
    SELECT 
        PWB.*,
        RANK() OVER (ORDER BY BadgeCount DESC, Score DESC) AS BadgeRank
    FROM 
        PostWithBadges PWB
)

SELECT 
    CASE 
        WHEN BP.BadgeCount > 0 THEN CONCAT(BP.OwnerDisplayName, ' (Earned ', BP.BadgeCount, ' Badges)')
        ELSE BP.OwnerDisplayName
    END AS PostOwner,
    BP.Title,
    BP.CreationDate,
    BP.Score,
    BP.ViewCount,
    BP.UpVoteCount,
    BP.DownVoteCount,
    BP.BadgeRank
FROM 
    RankedPosts BP
WHERE 
    BP.BadgeRank <= 10
ORDER BY 
    BP.BadgeRank, BP.CreationDate DESC
FETCH FIRST 5 ROWS ONLY;

-- Potentially including a subquery to calculate average votes per user.
SELECT 
    U.DisplayName,
    AVG(COALESCE(V.UpVoteCount, 0)) AS AvgUpVotes,
    AVG(COALESCE(V.DownVoteCount, 0)) AS AvgDownVotes
FROM 
    Users U
LEFT JOIN (
    SELECT 
        OwnerUserId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVoteCount
    FROM 
        Posts P
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    GROUP BY 
        OwnerUserId
) AS V ON U.Id = V.OwnerUserId
GROUP BY 
    U.DisplayName
HAVING 
    COUNT(U.Id) IS NOT NULL;

-- This final query will highlight any cases where users have not received any votes.
SELECT 
    U.DisplayName,
    COALESCE(V.UpVoteCount, 0) AS UpVoteCount,
    COALESCE(V.DownVoteCount, 0) AS DownVoteCount
FROM 
    Users U
LEFT JOIN (
    SELECT 
        OwnerUserId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVoteCount
    FROM 
        Posts P
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    GROUP BY 
        OwnerUserId
) AS V ON U.Id = V.OwnerUserId
WHERE 
    COALESCE(V.UpVoteCount, 0) = 0 AND COALESCE(V.DownVoteCount, 0) = 0
ORDER BY 
    U.DisplayName;
