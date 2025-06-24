WITH UserStatistics AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.Reputation, 
        U.CreationDate, 
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS CloseCount,
        AVG(COALESCE(P.Score, 0)) AS AvgScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE U.Reputation >= 1000
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
CloseReasons AS (
    SELECT 
        PH.UserId,
        PH.Comment AS CloseReason,
        COUNT(*) AS CloseReasonCount
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId = 10  -- Post Closed
    GROUP BY PH.UserId, PH.Comment
),
RankedUsers AS (
    SELECT 
        US.*, 
        ROW_NUMBER() OVER (PARTITION BY US.Reputation ORDER BY US.AvgScore DESC) AS UserRank
    FROM UserStatistics US
)
SELECT 
    R.UserId,
    R.DisplayName,
    R.Reputation,
    R.PostCount,
    R.AnswerCount,
    R.CloseCount,
    R.AvgScore,
    CR.CloseReason,
    COALESCE(CR.CloseReasonCount, 0) AS TotalCloseReasons
FROM RankedUsers R
LEFT JOIN CloseReasons CR ON R.UserId = CR.UserId
WHERE R.UserRank = 1 -- Select only top-ranked users per reputation group
ORDER BY R.Reputation DESC, R.AvgScore DESC
LIMIT 10;

-- This complex query does the following:
-- 1. Calculates user statistics including post and answer counts, close counts, and average scores.
-- 2. Generates a list of close reasons for posts closed by users.
-- 3. Ranks users by average score within their reputation groups.
-- 4. Finally, it selects only the top-ranked users for each reputation group along with their close reason count.
-- It utilizes CTEs, aggregate functions, CASE statements, and window functions to create a comprehensive analysis of users and their contributions.
