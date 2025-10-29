-- {"query": "1712.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3273} 

WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Location,
        U.Views AS TotalProfileViews,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(P.Score, 0)) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        MAX(GREATEST(COALESCE(P.LastActivityDate, '1900-01-01'), COALESCE(C.CreationDate, '1900-01-01'), U.LastAccessDate)) AS LastOverallActivity,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location,
        U.Views, U.UpVotes, U.DownVotes
),
PostQualityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpvotesReceived,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownvotesReceived,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 24) THEN 1 ELSE 0 END) AS EditHistoryCount, -- Include suggested edits applied
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeletedHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 19 THEN 1 ELSE 0 END) AS ProtectedHistoryCount,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 24) THEN PH.CreationDate ELSE NULL END) AS FirstEditTimestamp,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedTimestamp,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedTimestamp,
        -- Complex join on Tags via string matching for benchmarking
        STRING_AGG(DISTINCT T.TagName, ' | ') FILTER (WHERE T.TagName IS NOT NULL) AS AssociatedTagsString
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Tags T ON P.Tags LIKE CONCAT('%<', T.TagName, '>%') AND P.PostTypeId = 1 -- Inefficient string LIKE join for benchmarking
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastEditDate, P.ClosedDate, P.CommunityOwnedDate
),
TagUsageMetrics AS (
    SELECT
        UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')) AS TagName,
        P.Id AS PostId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
AggregatedTagStats AS (
    SELECT
        TUM.TagName,
        COUNT(DISTINCT TUM.PostId) AS TaggedPostsCount,
        AVG(TUM.Score) AS AvgScorePerTag,
        AVG(TUM.ViewCount) AS AvgViewCountPerTag,
        MAX(TUM.CreationDate) AS LatestPostDateForTag,
        (SELECT COUNT(DISTINCT U.Id) FROM Users U JOIN Badges B ON U.Id = B.UserId WHERE B.TagBased = TRUE AND B.Name = TUM.TagName) AS TagBadgeHolders
    FROM TagUsageMetrics TUM
    GROUP BY TUM.TagName
),
PostEventSequence AS (
    SELECT
        PH.PostId,
        PH.UserId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS EventDate,
        LAG(PH.PostHistoryTypeId, 1, 0) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEventType,
        LEAD(PH.PostHistoryTypeId, 1, 0) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS NextEventType,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS EventSequenceNum
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
)
SELECT
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.Location,
    UCS.TotalPostsOwned,
    UCS.QuestionsAsked,
    UCS.AnswersProvided,
    UCS.TotalPostScore,
    UCS.TotalCommentsMade,
    UCS.LastOverallActivity,
    UCS.GoldBadges,
    UCS.TagBasedBadges,
    COALESCE(SUM(PQM.EditHistoryCount), 0) AS TotalEditsAcrossPosts,
    COALESCE(SUM(PQM.ClosedHistoryCount), 0) AS TotalClosesAcrossPosts,
    COALESCE(SUM(PQM.DeletedHistoryCount), 0) AS TotalDeletesAcrossPosts,
    COALESCE(SUM(PQM.ProtectedHistoryCount), 0) AS TotalProtectionsAcrossPosts,
    COALESCE(SUM(PQM.DownvotesReceived), 0) AS TotalDownvotesOnPosts,
    -- Ratio of downvotes to upvotes on owned posts (using NULLIF for division by zero)
    NULLIF(CAST(SUM(PQM.DownvotesReceived) AS DECIMAL), 0) / NULLIF(CAST(SUM(PQM.UpvotesReceived) AS DECIMAL), 0) AS DownvoteUpvoteRatio,
    -- Average days between user creation and last recorded activity
    EXTRACT(EPOCH FROM (UCS.LastOverallActivity - UCS.UserCreationDate)) / (60 * 60 * 24) AS DaysActiveSinceCreation,
    -- Correlated Subquery: Count questions with accepted answers having a "too localized" close reason (CloseReasonId = 7 or 102)
    (
        SELECT COUNT(DISTINCT P_Inner.Id)
        FROM Posts P_Inner
        JOIN PostHistory PH_Inner ON P_Inner.Id = PH_Inner.PostId
        WHERE P_Inner.PostTypeId = 1
          AND P_Inner.OwnerUserId = UCS.UserId
          AND P_Inner.AcceptedAnswerId IS NOT NULL
          AND PH_Inner.PostHistoryTypeId = 10 -- Post Closed
          AND PH_Inner.Comment IN ('7', '102') -- Specific close reasons (Old: Too localized, Current: Off-topic)
    ) AS QuestionsClosedAsTooLocalizedWithAcceptedAnswer,
    -- Window Function: Rank users by their average post score within their location, considering only users with at least 5 posts
    RANK() OVER (PARTITION BY UCS.Location ORDER BY UCS.AvgPostScore DESC, UCS.Reputation DESC) AS RankByAvgPostScoreInLocation,
    -- Window Function + Correlated Subquery: Calculate the cumulative sum of post scores for a user's answers over time
    (
        SELECT SUM(InnerP.Score)
        FROM (
            SELECT
                P_Score.Score,
                P_Score.CreationDate,
                SUM(P_Score.Score) OVER (ORDER BY P_Score.CreationDate ROWS UNBOUNDED PRECEDING) AS CumulativeAnswerScore
            FROM Posts P_Score
            WHERE P_Score.OwnerUserId = UCS.UserId
            AND P_Score.PostTypeId = 2 -- Only answers
        ) AS InnerP
        ORDER BY InnerP.CreationDate DESC
        LIMIT 1 -- Get the final cumulative score
    ) AS FinalCumulativeAnswerScore,
    -- More complex calculation: Percentage of posts owned by the user that were last edited by someone else (not the owner)
    CAST(COUNT(DISTINCT CASE WHEN PQM.LastEditDate IS NOT NULL AND P_All.LastEditorUserId IS NOT NULL AND P_All.LastEditorUserId != UCS.UserId THEN PQM.PostId END) AS DECIMAL) * 100.0 / NULLIF(COUNT(DISTINCT PQM.PostId), 0) AS PercentPostsEditedByOthers,
    -- String expression: Count posts where the title contains 'SQL' AND 'join' or 'query' (case-insensitive)
    COUNT(DISTINCT CASE WHEN P_All.Title ILIKE '%SQL%' AND (P_All.Title ILIKE '%join%' OR P_All.Title ILIKE '%query%') THEN P_All.Id END) AS SqlJoinQueryPostsCount,
    -- Correlated Subquery: Check if a user has any posts that were closed and then reopened within a 30-day window
    COUNT(DISTINCT CASE WHEN PQM.ClosedHistoryCount > 0 AND PQM.ReopenedHistoryCount > 0 AND
                          EXISTS (
                            SELECT 1
                            FROM PostEventSequence PES_Closed
                            JOIN PostEventSequence PES_Reopened ON PES_Closed.PostId = PES_Reopened.PostId
                            WHERE PES_Closed.PostId = PQM.PostId
                              AND PES_Closed.PostHistoryTypeId = 10 -- Post Closed
                              AND PES_Reopened.PostHistoryTypeId = 11 -- Post Reopened
                              AND PES_Reopened.EventDate > PES_Closed.EventDate
                              AND PES_Reopened.EventDate <= PES_Closed.EventDate + INTERVAL '30 days' -- Reopened within 30 days
                          ) THEN PQM.PostId END) AS PostsRapidlyClosedThenReopened,
    -- Set Operator (simulated with correlated EXISTS on a UNION subquery):
    -- Users who have either posted a question AND have also posted an answer
    -- OR users who have posted a comment AND have also received a Gold Badge
    (
        SELECT COUNT(DISTINCT CombinedUsers.UserId)
        FROM (
            SELECT P_Q.OwnerUserId AS UserId FROM Posts P_Q WHERE P_Q.PostTypeId = 1 AND P_Q.OwnerUserId IS NOT NULL
            INTERSECT
            SELECT P_A.OwnerUserId AS UserId FROM Posts P_A WHERE P_A.PostTypeId = 2 AND P_A.OwnerUserId IS NOT NULL
            UNION
            SELECT C_U.UserId AS UserId FROM Comments C_U WHERE C_U.UserId IS NOT NULL
            INTERSECT
            SELECT B_U.UserId AS UserId FROM Badges B_U WHERE B_U.Class = 1 AND B_U.UserId IS NOT NULL
        ) AS CombinedUsers
        WHERE CombinedUsers.UserId = UCS.UserId
    ) AS ComplexEngagementIndicator,
    -- NULL Logic: Display 'No Tags' if AssociatedTagsString is NULL or empty
    COALESCE(PQM.AssociatedTagsString, 'No Tags') AS MainPostTagsDisplay
FROM UserContributionSummary UCS
LEFT JOIN PostQualityMetrics PQM ON UCS.UserId = PQM.OwnerUserId
LEFT JOIN Posts P_All ON PQM.PostId = P_All.Id -- Used for LastEditorUserId and Title checks
GROUP BY
    UCS.UserId, UCS.DisplayName, UCS.Reputation, UCS.CreationDate, UCS.LastAccessDate, UCS.Location,
    UCS.TotalPostsOwned, UCS.QuestionsAsked, UCS.AnswersProvided, UCS.TotalPostScore, UCS.AvgPostScore,
    UCS.TotalCommentsMade, UCS.LastOverallActivity, UCS.GoldBadges, UCS.TagBasedBadges,
    PQM.AssociatedTagsString -- Need to group by this if it's in SELECT and not aggregated
HAVING
    UCS.TotalPostsOwned > 10
    AND UCS.Reputation > 500
    AND (
        UCS.GoldBadges > 0
        OR EXISTS (SELECT 1 FROM AggregatedTagStats ATS WHERE ATS.TagName = 'postgresql' AND ATS.AvgScorePerTag > 15 AND ATS.TagBadgeHolders > 50)
    )
ORDER BY
    DownvoteUpvoteRatio DESC NULLS LAST,
    RankByAvgPostScoreInLocation ASC,
    TotalEditsAcrossPosts DESC,
    TotalProtectionsAcrossPosts DESC
LIMIT 100;
