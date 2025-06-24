
WITH UserBadgeCounts AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
ClosedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        PH.UserId AS ClosingUserId,
        PH.CreationDate AS CloseDate,
        PH.Comment AS CloseReason,
        @row_num := IF(@prev_post = P.Id, @row_num + 1, 1) AS CloseHistoryRank,
        @prev_post := P.Id
    FROM 
        Posts P
    JOIN 
        PostHistory PH ON P.Id = PH.PostId 
    CROSS JOIN (SELECT @row_num := 0, @prev_post := NULL) AS vars
    WHERE 
        PH.PostHistoryTypeId = 10  
),
QualifiedUsers AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes
    FROM 
        Users U
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName
)
SELECT 
    U.UserId,
    U.DisplayName,
    U.BadgeCount,
    COALESCE(CP.PostId, 0) AS PostId,
    COALESCE(CP.Title, 'No Closed Posts') AS ClosedPostTitle,
    COALESCE(CP.CloseDate, NULL) AS CloseDate,
    COALESCE(CP.CloseReason, 'N/A') AS CloseReason,
    (Q.TotalUpVotes - Q.TotalDownVotes) AS NetVotes
FROM 
    UserBadgeCounts U
LEFT JOIN 
    ClosedPosts CP ON U.UserId = CP.ClosingUserId AND CP.CloseHistoryRank = 1  
JOIN 
    QualifiedUsers Q ON U.UserId = Q.UserId
WHERE 
    (Q.TotalUpVotes - Q.TotalDownVotes) > 0  
ORDER BY 
    U.BadgeCount DESC, 
    NetVotes DESC
LIMIT 100;
