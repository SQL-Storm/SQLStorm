-- {"query": "1309.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2378} 

WITH HighReputationBadgeUsers AS (
    SELECT U.Id AS UserId
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation >= 50000 AND B.Class = 1 -- Gold badges
    GROUP BY U.Id
    HAVING COUNT(B.Id) >= 3
),
ActiveEditorUsers AS (
    SELECT PH.UserId
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6) -- Edits to Title, Body, Tags
    GROUP BY PH.UserId
    HAVING COUNT(PH.Id) >= 100
),
CoreInfluencerUsers AS (
    SELECT UserId FROM HighReputationBadgeUsers
    UNION -- Set operator usage: Combines users based on high reputation/badges OR extensive editing activity
    SELECT UserId FROM ActiveEditorUsers
),
UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScoreReceived,
        COUNT(DISTINCT PH_OwnEdit.Id) AS OwnPostEditCount,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class IN (1, 2)) AS GoldSilverBadgeCount, -- Postgres specific FILTER clause
        COALESCE(U.Views, 0) AS UserViews, -- NULL logic with COALESCE
        U.LastAccessDate,
        U.AboutMe
    FROM Users U
    JOIN CoreInfluencerUsers CIU ON U.Id = CIU.UserId -- Joins to the result of the UNION
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN PostHistory PH_OwnEdit ON P.Id = PH_OwnEdit.PostId
        AND U.Id = PH_OwnEdit.UserId
        AND PH_OwnEdit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.LastAccessDate, U.AboutMe
),
PostQualityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.Title,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.Tags,
        (P.Score * 0.7 + COALESCE(P.ViewCount, 0) * 0.05 + COALESCE(P.AnswerCount, 0) * 1.0 + COALESCE(P.FavoriteCount, 0) * 1.5) AS EngagementScore, -- Complicated calculation
        AVG(C.Score) OVER (PARTITION BY P.Id) AS AvgCommentScoreForPost, -- Window function: average comment score per post
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS Rn_UserBestPost, -- Window function: ranks posts per user
        EXTRACT(DAY FROM (COALESCE(P.LastEditDate, P.CreationDate) - P.CreationDate)) AS DaysSinceLastEdit, -- Date expression/calculation
        SUM(CASE WHEN PH_Edit.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) OVER (PARTITION BY P.Id) AS PostEditCount -- Window function: count edits per post
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Only consider questions
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH_Edit ON P.Id = PH_Edit.PostId
),
HeavyEditorsAllPosts AS (
    -- Users who have made a significant number of edits to any post
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalEditsToAnyPost,
        RANK() OVER (ORDER BY COUNT(PH.Id) DESC) AS EditRankOverall -- Window function: rank users by total edits
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4,5,6,8,9) -- Edits and Rollbacks
    GROUP BY PH.UserId
    HAVING COUNT(PH.Id) > 50
),
ModeratorHistorySummary AS (
    -- Users who have participated in closing/reopening posts
    SELECT
        PH.UserId,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 10) AS CloseVotesParticipated, -- Postgres specific FILTER clause
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 11) AS ReopenVotesParticipated
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11)
    GROUP BY PH.UserId
    HAVING COUNT(PH.Id) >= 5
)
SELECT
    UEM.UserId,
    UEM.DisplayName,
    UEM.Reputation,
    UEM.TotalPosts,
    UEM.TotalQuestions,
    UEM.TotalAnswers,
    UEM.OwnPostEditCount,
    UEM.GoldSilverBadgeCount,
    PQM.Title AS TopQuestionTitle,
    PQM.EngagementScore AS TopQuestionEngagementScore,
    PQM.AvgCommentScoreForPost AS TopQuestionAvgCommentScore,
    UEM.UserViews,
    HEA.TotalEditsToAnyPost AS AllPostEditsCount,
    MHS.CloseVotesParticipated,
    MHS.ReopenVotesParticipated,
    (SELECT COUNT(DISTINCT PL.RelatedPostId)
     FROM PostLinks PL
     WHERE PL.PostId = PQM.PostId AND PL.LinkTypeId = 3
       AND EXISTS (SELECT 1 FROM Posts SubP WHERE SubP.Id = PL.RelatedPostId AND SubP.Score > 100)) AS DuplicatesToHighScorePostsCount, -- Correlated subquery
    LAG(UEM.Reputation, 1, 0) OVER (ORDER BY UEM.Reputation DESC) AS PreviousReputation, -- Window function: value from previous row
    NTILE(5) OVER (ORDER BY UEM.Reputation DESC) AS ReputationQuintile, -- Window function: assigns users to reputation quintiles
    CASE
        WHEN UEM.Reputation >= 100000 AND UEM.GoldSilverBadgeCount >= 10 THEN 'Elite Legend'
        WHEN UEM.Reputation >= 50000 AND UEM.TotalQuestions >= 50 AND UEM.TotalAnswers >= 200 THEN 'Grand Master Contributor'
        WHEN UEM.OwnPostEditCount >= 50 AND HEA.TotalEditsToAnyPost >= 200 THEN 'Proactive Editor'
        ELSE 'Active Influencer'
    END AS UserInfluenceCategory, -- Complicated CASE expression
    COALESCE(U.Location, 'Unknown') AS UserLocation, -- NULL logic with COALESCE
    NULLIF(TRIM(SUBSTRING(UEM.AboutMe, 1, 150)), '') AS AboutMeSummary, -- String manipulation & NULLIF
    COALESCE(array_length(string_to_array(substring(PQM.Tags, 2, length(PQM.Tags)-2), '><'), 1), 0) AS TopQuestionTagCount, -- String expression for tag parsing
    (SELECT AVG(V.BountyAmount) FROM Votes V WHERE V.UserId = UEM.UserId AND V.VoteTypeId = 8 AND V.BountyAmount IS NOT NULL) AS AvgBountyStartedAmount, -- Scalar subquery
    (SELECT SUM(V.BountyAmount) FROM Votes V JOIN Posts P_Bounty ON V.PostId = P_Bounty.Id WHERE P_Bounty.OwnerUserId = UEM.UserId AND V.VoteTypeId = 9 AND V.BountyAmount IS NOT NULL) AS TotalBountyReceivedAmount, -- Scalar subquery
    P.CreationDate AS UserCreationDateRaw,
    UEM.LastAccessDate AS UserLastAccessDateRaw
FROM UserEngagementMetrics UEM
JOIN PostQualityMetrics PQM ON UEM.UserId = PQM.OwnerUserId
LEFT JOIN HeavyEditorsAllPosts HEA ON UEM.UserId = HEA.UserId -- Outer join
LEFT JOIN ModeratorHistorySummary MHS ON UEM.UserId = MHS.UserId -- Outer join
LEFT JOIN Users U ON UEM.UserId = U.Id -- Re-join to get raw User data not aggregated in UEM for `Location` and `WebsiteUrl` checks
WHERE
    PQM.Rn_UserBestPost = 1 -- Select only the best performing question for each user
    AND UEM.Reputation > 10000 -- Base reputation filter
    AND UEM.TotalPosts > 50 -- Minimum posts
    AND UEM.OwnPostEditCount >= 10 -- Minimum self-edits
    AND UEM.GoldSilverBadgeCount >= 3 -- Minimum high-class badges
    AND PQM.PostCreationDate > (CURRENT_TIMESTAMP - INTERVAL '3 year') -- Recent post activity, date expression
    AND PQM.DaysSinceLastEdit >= 14 -- Posts that have seen significant edit time since creation
    AND (LOWER(PQM.Title) LIKE '%api%' OR LOWER(PQM.Title) LIKE '%cloud%' OR LOWER(PQM.Tags) LIKE '%<javascript>%' OR LOWER(PQM.Tags) LIKE '%<python>%') -- String predicate with OR logic
    AND NOT EXISTS (SELECT 1 FROM Comments C WHERE C.PostId = PQM.PostId AND C.Score < -3 AND C.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')) -- Negative comment filtering using NOT EXISTS subquery
    AND (U.Location IS NOT NULL OR U.WebsiteUrl IS NOT NULL) -- NULL logic for location/website
ORDER BY
    UEM.Reputation DESC,
    PQM.EngagementScore DESC,
    UEM.LastAccessDate DESC
LIMIT 200;
