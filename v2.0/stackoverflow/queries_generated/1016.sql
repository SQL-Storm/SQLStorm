-- {"query": "1016.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2850} 

WITH UserActivitySummary AS (
    -- Summarize user post and comment activity, reputation, and badge counts.
    -- Includes correlated subqueries for badge counts for each user.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT PA.Id) AS TotalAnswersOwned,
        COUNT(DISTINCT PQ.Id) AS TotalQuestionsOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(P.Score) AS TotalPostScoreOwned,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScoreMade,
        MAX(P.LastActivityDate) AS LatestPostActivityDate,
        MAX(C.CreationDate) AS LatestCommentActivityDate,
        (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 3) AS BronzeBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts PA ON U.Id = PA.OwnerUserId AND PA.PostTypeId = 2 -- Answers
    LEFT JOIN Posts PQ ON U.Id = PQ.OwnerUserId AND PQ.PostTypeId = 1 -- Questions
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.Reputation > 1000 AND U.LastAccessDate >= NOW() - INTERVAL '3 year' -- Filter for active users with decent reputation
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
RecentPostEngagement AS (
    -- Analyze recent post engagement (questions/answers) including scores, views, and tag categorization.
    -- Uses window functions for ranking and moving averages.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.LastActivityDate,
        EXTRACT(YEAR FROM P.CreationDate) AS CreationYear,
        EXTRACT(MONTH FROM P.CreationDate) AS CreationMonth,
        -- Rank posts by score within their creation month/year, handling ties with view count
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM P.CreationDate), EXTRACT(MONTH FROM P.CreationDate) ORDER BY P.Score DESC, P.ViewCount DESC) AS RankInMonthByScore,
        -- Calculate the average score of posts by the same user within a 60-day sliding window
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate RANGE BETWEEN INTERVAL '60 days' PRECEDING AND CURRENT ROW) AS AvgScoreLast60DaysByUser,
        -- Categorize posts based on common programming language tags, handling NULL tags
        CASE
            WHEN P.Tags IS NULL THEN 'Untagged'
            WHEN P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<postgresql>%' OR P.Tags LIKE '%<mysql>%' THEN 'SQL_Database_Related'
            WHEN P.Tags LIKE '%<javascript>%' OR P.Tags LIKE '%<node.js>%' OR P.Tags LIKE '%<reactjs>%' THEN 'JavaScript_Frontend_Related'
            WHEN P.Tags LIKE '%<python>%' OR P.Tags LIKE '%<django>%' OR P.Tags LIKE '%<flask>%' THEN 'Python_Related'
            ELSE 'Other_Technology'
        END AS TechnologyCategory,
        COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerPostId_IfQuestion
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Only Questions (1) and Answers (2)
      AND P.CreationDate >= NOW() - INTERVAL '2 year' -- Focus on recent posts
      AND P.Score > 0 -- Only posts with positive scores
      AND P.ViewCount > 10 -- And a minimum view count
),
PostHistoricalModifications AS (
    -- Track distinct editors and significant edit types for posts.
    -- Uses FIRST_VALUE window function to get initial editor and edit date.
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.UserId) AS UniqueEditorCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE NULL END) AS TotalEditRollbackActions,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS BodyTitleTagEditsCount,
        FIRST_VALUE(PH.UserId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC) AS InitialEditorUserId,
        FIRST_VALUE(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate ASC) AS FirstModificationDate,
        MAX(PH.CreationDate) AS LastModificationDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20) -- Edits, Rollbacks, Close/Reopen, Lock/Unlock, Protect/Unprotect
    GROUP BY PH.PostId
    HAVING COUNT(DISTINCT PH.UserId) > 1 OR COUNT(PH.Id) > 3 -- Posts with multiple editors or many modifications
),
DuplicatePostIdentification AS (
    -- Identify posts marked as duplicates, their original post, the user who closed them, and the reason.
    SELECT
        PL.PostId AS DuplicatePostId,
        PL.RelatedPostId AS OriginalQuestionId,
        PH.UserId AS ClosedByModeratorOrUser,
        CAST(PH.Comment AS smallint) AS CloseReasonTypeId,
        CRT.Name AS CloseReasonTypeName,
        PL.CreationDate AS LinkCreationDate
    FROM PostLinks PL
    JOIN PostHistory PH ON PL.PostId = PH.PostId AND PH.PostHistoryTypeId = 10 -- Post Closed event
    LEFT JOIN CloseReasonTypes CRT ON CAST(PH.Comment AS smallint) = CRT.Id -- Join to get close reason name
    WHERE PL.LinkTypeId = 3 -- LinkType 3 indicates a duplicate
      AND PH.CreationDate >= NOW() - INTERVAL '3 year' -- Recent closure events
),
CombinedPostMetrics AS (
    -- Combine recent post engagement with modification history and duplicate information.
    SELECT
        RPE.PostId,
        RPE.PostTypeId,
        RPE.OwnerUserId,
        RPE.PostCreationDate,
        RPE.PostScore,
        RPE.ViewCount,
        RPE.AnswerCount,
        RPE.FavoriteCount,
        RPE.LastActivityDate,
        RPE.TechnologyCategory,
        RPE.RankInMonthByScore,
        RPE.AvgScoreLast60DaysByUser,
        COALESCE(PHM.UniqueEditorCount, 0) AS PostUniqueEditorCount,
        COALESCE(PHM.BodyTitleTagEditsCount, 0) AS PostSignificantEditsCount,
        PHM.InitialEditorUserId AS PostInitialEditorId,
        DPI.OriginalQuestionId AS IsDuplicateOfQuestionId,
        DPI.ClosedByModeratorOrUser AS DuplicateClosedByUserId,
        DPI.CloseReasonTypeName AS DuplicateCloseReason
    FROM RecentPostEngagement RPE
    LEFT JOIN PostHistoricalModifications PHM ON RPE.PostId = PHM.PostId
    LEFT JOIN DuplicatePostIdentification DPI ON RPE.PostId = DPI.DuplicatePostId
)
-- Final aggregation to produce a comprehensive benchmark result.
-- Combines all CTEs, applies complex filtering, window functions, and advanced expressions.
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.UserProfileViews,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    SUM(CPM.PostScore) AS TotalRecentPostScore,
    AVG(CPM.ViewCount) AS AverageRecentPostViewCount,
    COUNT(DISTINCT CPM.PostId) AS CountRecentActivePosts,
    COUNT(DISTINCT CASE WHEN CPM.TechnologyCategory = 'SQL_Database_Related' THEN CPM.PostId ELSE NULL END) AS RecentSQLPostsCount,
    COUNT(DISTINCT CASE WHEN CPM.IsDuplicateOfQuestionId IS NOT NULL THEN CPM.PostId ELSE NULL END) AS RecentDuplicatePostsCount,
    COUNT(DISTINCT CASE WHEN CPM.PostSignificantEditsCount >= 2 THEN CPM.PostId ELSE NULL END) AS RecentMultiEditedPostsCount,
    -- NTILE window function to categorize users into 4 performance tiers based on their total recent post score
    NTILE(4) OVER (ORDER BY SUM(CPM.PostScore) DESC, AVG(CPM.ViewCount) DESC) AS UserPerformanceTier,
    -- Complicated expression: Ratio of Gold badges to significant edits on their posts (avoiding division by zero)
    CASE
        WHEN SUM(CPM.PostSignificantEditsCount) > 0 THEN CAST(UAS.GoldBadges AS NUMERIC) / SUM(CPM.PostSignificantEditsCount)
        ELSE 0.0
    END AS GoldBadgeToSignificantEditRatio,
    -- Non-correlated subquery to find the user's most active year/month based on post creation
    (
        SELECT TO_CHAR(DATE_TRUNC('month', P.CreationDate), 'YYYY-MM')
        FROM Posts P
        WHERE P.OwnerUserId = UAS.UserId
        GROUP BY DATE_TRUNC('month', P.CreationDate)
        ORDER BY COUNT(P.Id) DESC, SUM(P.Score) DESC
        LIMIT 1
    ) AS UserMostActiveMonth,
    -- Boolean check using EXISTS subquery: Has the user self-accepted an answer to one of their own questions?
    EXISTS (
        SELECT 1
        FROM Posts Q
        JOIN Posts A ON Q.AcceptedAnswerId = A.Id
        WHERE Q.OwnerUserId = UAS.UserId
          AND A.OwnerUserId = UAS.UserId
          AND Q.PostTypeId = 1 -- Is a question
          AND A.PostTypeId = 2 -- Is an answer
          AND Q.CreationDate >= NOW() - INTERVAL '5 year' -- In a reasonable timeframe
    ) AS HasSelfAcceptedAnswerForOwnQuestion,
    -- Lag window function to compare current year's recent post score with previous year's recent post score (if data allows)
    LAG(SUM(CPM.PostScore), 1, 0) OVER (PARTITION BY UAS.UserId ORDER BY EXTRACT(YEAR FROM CPM.PostCreationDate)) AS PreviousYearRecentPostScore
FROM UserActivitySummary UAS
LEFT JOIN CombinedPostMetrics CPM ON UAS.UserId = CPM.OwnerUserId
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserCreationDate, UAS.UserProfileViews,
    UAS.GoldBadges, UAS.SilverBadges, UAS.BronzeBadges, UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned, UAS.TotalAnswersOwned, EXTRACT(YEAR FROM CPM.PostCreationDate) -- Include for LAG partitioning
HAVING
    COUNT(CPM.PostId) > 10 -- Users with at least 10 recent posts
    AND SUM(CPM.PostScore) > 50 -- And a total recent score over 50
    AND UAS.Reputation >= 2000 -- And a minimum reputation
ORDER BY
    UserPerformanceTier ASC,
    TotalRecentPostScore DESC,
    UAS.Reputation DESC,
    UAS.DisplayName
LIMIT 500;
