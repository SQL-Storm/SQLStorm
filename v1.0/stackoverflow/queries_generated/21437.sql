WITH UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
),
PostWithTagCounts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        COUNT(T.Id) AS TagCount,
        P.Score,
        P.OwnerUserId,
        COALESCE(P.ClosedDate, '9999-12-31') AS CloseDate
    FROM Posts P
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(P.Tags, 2, length(P.Tags) - 2), '><')) AS TagName
    ) T ON TRUE
    GROUP BY P.Id
),
ActiveAndClosedPosts AS (
    SELECT 
        P.PostId,
        P.Title,
        COUNT(C.Id) AS CommentCount,
        SUM(CASE WHEN P.CloseDate < CURRENT_TIMESTAMP THEN 1 ELSE 0 END) AS ClosedCount,
        SUM(CASE WHEN P.CloseDate = '9999-12-31' THEN 1 ELSE 0 END) AS ActiveCount
    FROM PostWithTagCounts P
    LEFT JOIN Comments C ON P.PostId = C.PostId
    GROUP BY P.PostId, P.Title
),
UserBadges AS (
    SELECT 
        B.UserId,
        COUNT(B.Id) AS BadgeCount,
        MAX(B.Class) AS HighestBadgeClass
    FROM Badges B
    GROUP BY B.UserId
)
SELECT 
    UR.DisplayName,
    UR.Reputation,
    COALESCE(UB.BadgeCount, 0) AS BadgeCount,
    COALESCE(UB.HighestBadgeClass, 0) AS HighestBadgeClass,
    ACP.Title,
    ACP.CommentCount,
    ACP.ClosedCount,
    ACP.ActiveCount
FROM UserReputation UR
LEFT JOIN UserBadges UB ON UR.UserId = UB.UserId
JOIN ActiveAndClosedPosts ACP ON UR.UserId = ACP.PostId -- Joining with appropriate logic for users and posts
WHERE 
    (UR.Reputation > 1000 OR ACP.CommentCount > 5)
    AND (ACP.ClosedCount = 0 OR ACP.ActiveCount < 5)
    AND (UB.BadgeCount IS NULL OR UB.BadgeCount > 2)
ORDER BY UR.Reputation DESC, ACP.CommentCount DESC
LIMIT 100;

-- The above query investigates users along with their reputation, badge counts,
-- and their activity in terms of post comments and closure counts. Uses CTEs, 
-- correlation with outer joins, and incorporates diverse conditions and aggregates.
