-- {"query": "1555.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3002} 
WITH UserMetrics AS (
    -- CTE 1: Aggregated user statistics, including derived metrics and correlated subqueries
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostsScore,
        AVG(COALESCE(P.Score, 0.0)) AS AvgPostScoreOwned,
        COUNT(C.Id) AS TotalCommentsMade,
        -- Correlated subquery: Get the most recent gold badge date
        (SELECT MAX(B_gold.Date) FROM Badges B_gold WHERE B_gold.UserId = U.Id AND B_gold.Class = 1) AS LastGoldBadgeDate,
        -- Correlated subquery: Count edits made by this user to any posts
        (SELECT COUNT(DISTINCT PH_edit.PostId) FROM PostHistory PH_edit WHERE PH_edit.UserId = U.Id AND PH_edit.PostHistoryTypeId IN (4, 5, 6)) AS TotalEditsMadeByThisUser,
        -- Complex calculation: Account age in days
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (24 * 3600) AS AccountAgeDays,
        -- Conditional expression (CASE): User reputation tier
        CASE
            WHEN U.Reputation >= 200000 THEN 'Legendary Contributor'
            WHEN U.Reputation >= 50000 THEN 'Expert Community Member'
            WHEN U.Reputation >= 10000 THEN 'Active Participant'
            ELSE 'Newcomer or Casual'
        END AS ReputationTier
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
),
PostDetailStats AS (
    -- CTE 2: Detailed post statistics, including window functions and string parsing
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
        LENGTH(P.Body) AS BodyLength,
        -- String expression: Clean and get tags string
        COALESCE(NULLIF(TRIM(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2)), ''), '') AS TagsCleanString,
        -- String expression & calculation: Count of tags
        COALESCE(ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'), 1), 0) AS TagCount,
        -- Window function: Rank posts by score within their type
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostScoreRankType,
        -- Window function: Calculate average score for posts created in the same month
        AVG(P.Score) OVER (PARTITION BY DATE_TRUNC('month', P.CreationDate)) AS AvgMonthlyPostScore,
        -- Non-correlated subquery: Count unique users who upvoted this post
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UniqueUpvotersCount,
        -- Check for specific history types (e.g., closed/reopened status from PostHistory)
        MAX(CASE WHEN PH_closed.PostHistoryTypeId IN (10, 101) THEN 1 ELSE 0 END) AS WasEverClosed,
        MAX(CASE WHEN PH_reopened.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasEverReopened,
        -- NULL logic: Count comments from registered vs. unregistered users
        COUNT(CASE WHEN C.UserId IS NULL THEN C.Id ELSE NULL END) AS UnregisteredComments,
        COUNT(CASE WHEN C.UserId IS NOT NULL THEN C.Id ELSE NULL END) AS RegisteredComments,
        -- String expression: Check for specific phrases in body (case-insensitive)
        CASE WHEN P.Body ILIKE '%performance%' OR P.Body ILIKE '%optimization%' THEN TRUE ELSE FALSE END AS ContainsPerformanceKeyword
    FROM Posts P
    LEFT JOIN PostHistory PH_closed ON P.Id = PH_closed.PostId AND PH_closed.PostHistoryTypeId IN (10, 101)
    LEFT JOIN PostHistory PH_reopened ON P.Id = PH_reopened.PostId AND PH_reopened.PostHistoryTypeId = 11
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Body, P.Tags
),
RecentPostHistory AS (
    -- CTE 3: Latest revision details for posts, using ROW_NUMBER for selecting associated values
    SELECT
        PH.PostId,
        PH.CreationDate AS LatestHistoryDate,
        PH.RevisionGUID AS LatestRevisionGUID,
        PH.Comment AS LatestHistoryComment,
        PH.Text AS LatestHistoryText
    FROM (
        SELECT
            PH_inner.*,
            ROW_NUMBER() OVER (PARTITION BY PH_inner.PostId ORDER BY PH_inner.CreationDate DESC, PH_inner.Id DESC) as rn
        FROM PostHistory PH_inner
    ) PH
    WHERE PH.rn = 1
),
HighlyEngagedPosts AS (
    -- CTE 4: Posts with high engagement or specific characteristics, combined using UNION ALL
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate,
        'High_Score_Question' AS EngagementType
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Score > 50 AND P.AnswerCount > 2
    UNION ALL
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate,
        'Active_Answer' AS EngagementType
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.Score > 20 AND P.CommentCount > 5
)
-- Main Query: Joins all CTEs and other tables, applies complex filters and calculations
SELECT
    UM.UserId,
    UM.DisplayName,
    UM.Reputation,
    UM.ReputationTier,
    UM.AccountAgeDays,
    UM.TotalPostsOwned,
    UM.TotalQuestionsOwned,
    UM.TotalAnswersOwned,
    UM.TotalPostsScore,
    UM.AvgPostScoreOwned,
    UM.TotalCommentsMade,
    UM.LastGoldBadgeDate,
    UM.TotalEditsMadeByThisUser,
    PDS.PostId,
    PDS.PostTypeId,
    PDS.PostCreationDate,
    PDS.PostScore,
    PDS.ViewCount,
    PDS.AnswerCount,
    PDS.CommentCount,
    PDS.FavoriteCount,
    PDS.BodyLength,
    PDS.TagCount,
    PDS.PostScoreRankType,
    PDS.AvgMonthlyPostScore,
    PDS.UniqueUpvotersCount,
    PDS.WasEverClosed,
    PDS.WasEverReopened,
    PDS.UnregisteredComments,
    PDS.RegisteredComments,
    PDS.ContainsPerformanceKeyword,
    RPH.LatestHistoryDate,
    RPH.LatestRevisionGUID,
    RPH.LatestHistoryComment,
    RPH.LatestHistoryText,
    COALESCE(B.Name, 'No Recent Badge') AS LatestBadgeName, -- NULL logic, string literal
    COALESCE(B.Class, -1) AS LatestBadgeClass,
    LT.Name AS LinkedPostTypeName,
    PL.RelatedPostId,
    TT.TagName AS PrimaryTagName,
    TT.Count AS PrimaryTagUseCount,
    HE.EngagementType, -- From UNION ALL CTE
    -- Complex predicate/calculation: Ratio of UpVotes to DownVotes, handling division by zero
    CASE
        WHEN UM.UserTotalDownVotes = 0 THEN
            CASE WHEN UM.UserTotalUpVotes > 0 THEN 9999.99 -- Arbitrarily high value for infinite ratio
            ELSE 0.0 END
        ELSE UM.UserTotalUpVotes * 1.0 / UM.UserTotalDownVotes
    END AS UpDownVoteRatio,
    -- Correlated subquery in SELECT: Get the body length of the accepted answer, if any, posted by the user
    (SELECT LENGTH(PA.Body)
     FROM Posts Q_inner
     JOIN Posts PA ON Q_inner.AcceptedAnswerId = PA.Id
     WHERE Q_inner.Id = PDS.PostId AND Q_inner.PostTypeId = 1 AND PA.OwnerUserId = UM.UserId
    ) AS AcceptedAnswerBodyLengthByOwner,
    -- String expression and NULL logic: If tags exist, get first tag; otherwise, 'Untagged'
    COALESCE(
        (CASE WHEN PDS.TagCount > 0 THEN (string_to_array(PDS.TagsCleanString, '><'))[1] ELSE NULL END),
        'Untagged'
    ) AS FirstTagInList,
    -- Correlated subquery: Determine if a post had edits from multiple distinct registered users
    (
        SELECT
            CASE WHEN COUNT(DISTINCT PH_edit_users.UserId) > 1 THEN TRUE ELSE FALSE END
        FROM PostHistory PH_edit_users
        WHERE PH_edit_users.PostId = PDS.PostId
          AND PH_edit_users.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
          AND PH_edit_users.UserId IS NOT NULL
    ) AS HasMultiUserEdits,
    -- Calculation: Days between user's creation and post's creation
    EXTRACT(EPOCH FROM (PDS.PostCreationDate - UM.CreationDate)) / (24 * 3600) AS DaysBetweenUserCreationAndPost
FROM UserMetrics UM
LEFT JOIN PostDetailStats PDS ON UM.UserId = PDS.OwnerUserId
LEFT JOIN RecentPostHistory RPH ON PDS.PostId = RPH.PostId
LEFT JOIN Badges B ON UM.UserId = B.UserId AND B.Date = UM.LastGoldBadgeDate -- Assumes LastGoldBadgeDate is unique per user per day; for multiple badges on same day, one is picked arbitrarily
LEFT JOIN PostLinks PL ON PDS.PostId = PL.PostId
LEFT JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
LEFT JOIN Tags TT ON PDS.TagCount > 0 AND PDS.PostTypeId = 1 -- Only join primary tag to questions with tags
   AND TT.TagName = (string_to_array(PDS.TagsCleanString, '><'))[1]
LEFT JOIN HighlyEngagedPosts HE ON PDS.PostId = HE.PostId AND PDS.OwnerUserId = HE.OwnerUserId -- Join with UNION ALL CTE
WHERE UM.Reputation >= 10000 -- Filter for significant users
  AND PDS.PostScore IS NOT NULL AND PDS.PostScore > 0 -- Filter for meaningful posts
  AND PDS.PostTypeId IN (1, 2) -- Focus on Questions and Answers
  AND PDS.WasEverClosed = 0 -- Exclude closed posts
  AND (PDS.FavoriteCount IS NOT NULL AND PDS.FavoriteCount > 0 OR PDS.ViewCount > 500) -- Complex predicate with NULL logic
  AND PDS.ContainsPerformanceKeyword = TRUE -- Specific string expression filter
  -- Correlated subquery in WHERE: Only include posts that have at least one comment by a user with > 500 reputation
  AND EXISTS (
      SELECT 1
      FROM Comments C_filter
      INNER JOIN Users U_filter ON C_filter.UserId = U_filter.Id
      WHERE C_filter.PostId = PDS.PostId AND U_filter.Reputation > 500
  )
ORDER BY
    UM.Reputation DESC,
    PDS.PostScore DESC,
    UM.LastAccessDate DESC,
    RPH.LatestHistoryDate DESC
LIMIT 5000;