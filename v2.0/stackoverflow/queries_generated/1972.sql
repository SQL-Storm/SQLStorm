-- {"query": "1972.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4027} 

WITH UserContributionSummary AS (
    -- CTE 1: Summarize core user contributions including posts, comments, and total badges.
    -- Aggregates various activities for each user.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId IN (1,2,3,4,5,6,7,8)), 0) AS TotalPosts,
        COALESCE(COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1), 0) AS TotalQuestions,
        COALESCE(COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2), 0) AS TotalAnswers,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalComments,
        AVG(CASE WHEN P.PostTypeId IN (1,2) THEN P.Score ELSE NULL END) AS AvgPostScore,
        COUNT(DISTINCT B.Id) AS TotalBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
UserVoteSummary AS (
    -- CTE 2: Summarize votes received on posts owned by each user.
    -- This helps differentiate votes received on a user's content versus votes given by the user.
    SELECT
        P.OwnerUserId AS UserId,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceivedOnPosts
    FROM Posts AS P
    JOIN Votes AS V ON P.Id = V.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
CorrectedUserContributionSummary AS (
    -- CTE 3: Combines core user contributions with the vote summaries.
    -- Calculates a composite 'UserEngagementScore' based on multiple factors.
    SELECT
        UCS.UserId,
        UCS.DisplayName,
        UCS.Reputation,
        UCS.UserCreationDate,
        UCS.LastAccessDate,
        UCS.TotalPosts,
        UCS.TotalQuestions,
        UCS.TotalAnswers,
        UCS.TotalComments,
        UCS.AvgPostScore,
        COALESCE(UVS.TotalUpvotesReceivedOnPosts, 0) AS TotalUpvotesReceived,
        COALESCE(UVS.TotalDownvotesReceivedOnPosts, 0) AS TotalDownvotesReceived,
        UCS.TotalBadges,
        -- Elaborate calculation for UserEngagementScore, weighted by different activity types
        CAST(
            (UCS.Reputation * 0.1) +
            (UCS.TotalPosts * 0.5) +
            (UCS.TotalComments * 0.2) +
            (COALESCE(UVS.TotalUpvotesReceivedOnPosts, 0) * 1.0) -
            (COALESCE(UVS.TotalDownvotesReceivedOnPosts, 0) * 0.8) +
            (UCS.TotalBadges * 2.0) +
            (EXTRACT(EPOCH FROM (NOW() - UCS.LastAccessDate)) / 86400 * -0.01) -- Penalize for inactivity
        AS NUMERIC(15, 2)) AS UserEngagementScore
    FROM UserContributionSummary AS UCS
    LEFT JOIN UserVoteSummary AS UVS ON UCS.UserId = UVS.UserId
),
RevisionAndCloseHistory AS (
    -- CTE 4: Analyzes post history for edits, closures, and reopens.
    -- Uses a regular expression `~ '^[0-9]+$'` for robust numeric validation before casting `Comment` to `SMALLINT`.
    -- Calculates time to first edit using `EXTRACT(EPOCH FROM ...)`.
    SELECT
        PH.PostId,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS TotalEdits,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS TotalCloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS TotalReopenEvents,
        STRING_AGG(DISTINCT CRT.Name, ', ') FILTER (
            WHERE PH.PostHistoryTypeId = 10
              AND PH.Comment IS NOT NULL
              AND PH.Comment ~ '^[0-9]+$'
        ) AS DistinctCloseReasons,
        EXTRACT(EPOCH FROM (MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) - P.CreationDate)) / 3600 AS HoursToFirstEdit
    FROM PostHistory AS PH
    JOIN Posts AS P ON PH.PostId = P.Id
    LEFT JOIN CloseReasonTypes AS CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$' AND CAST(PH.Comment AS SMALLINT) = CRT.Id
    GROUP BY PH.PostId, P.CreationDate
),
TagAggregateStats AS (
    -- CTE 5: Aggregates performance metrics for a specific set of 'hot' or 'technical' tags.
    -- Uses a LATERAL join to efficiently filter posts containing relevant tags.
    -- Calculates a 'TagHotnessIndex'.
    SELECT
        T.TagName,
        COUNT(DISTINCT P.Id) AS NumberOfTaggedQuestions,
        AVG(P.Score) AS AvgQuestionScore,
        AVG(P.ViewCount) AS AvgQuestionViewCount,
        SUM(P.FavoriteCount) AS TotalQuestionFavoriteCount,
        -- Complex calculation for TagHotnessIndex, weighting score, views, favorites, and answers.
        CAST(
            (COALESCE(AVG(P.Score), 0) * 0.6) +
            (COALESCE(AVG(P.ViewCount), 0) * 0.005) +
            (COALESCE(SUM(P.FavoriteCount), 0) * 0.1) +
            (COALESCE(SUM(P.AnswerCount), 0) * 1.5)
        AS NUMERIC(10, 2)) AS TagHotnessIndex
    FROM Tags AS T
    JOIN LATERAL (
        SELECT P_Inner.Id, P_Inner.Score, P_Inner.ViewCount, P_Inner.FavoriteCount, P_Inner.AnswerCount, P_Inner.Tags
        FROM Posts AS P_Inner
        WHERE P_Inner.PostTypeId = 1 AND P_Inner.Tags LIKE '%' || T.TagName || '%'
          AND P_Inner.ClosedDate IS NULL
    ) AS P ON TRUE
    WHERE T.TagName IN ('sql', 'database', 'performance', 'indexing', 'query-optimization', 'postgresql', 'mysql', 'mssql', 'optimization', 'bigdata', 'nosql', 'json', 'data-modeling', 'etl')
    GROUP BY T.TagName
),
AdvancedUserBadgeStats AS (
    -- CTE 6: Provides advanced insights into user badges and their historical post performance.
    -- Uses `ROW_NUMBER()` as a window function to rank users by reputation within badge classes.
    -- Includes correlated subqueries to analyze post scores before badge acquisition and comment activity after a 'Gold' badge.
    SELECT
        U.Id AS UserId,
        B.Name AS BadgeName,
        B.Date AS BadgeAwardDate,
        B.Class AS BadgeClass,
        ROW_NUMBER() OVER (PARTITION BY B.Class ORDER BY U.Reputation DESC, U.Id ASC) AS RankInBadgeClass,
        -- Correlated subquery: Calculates the average score of posts created by this user
        -- before they received this specific badge.
        (SELECT AVG(P_Inner.Score)
         FROM Posts AS P_Inner
         WHERE P_Inner.OwnerUserId = U.Id
           AND P_Inner.CreationDate < B.Date
           AND P_Inner.PostTypeId IN (1, 2)
        ) AS AvgPreBadgePostScore,
        -- Correlated subquery: Counts comments made by the user on posts *they do not own*
        -- after receiving a Class 1 (Gold) badge.
        (SELECT COUNT(C_Inner.Id)
         FROM Comments AS C_Inner
         JOIN Posts AS P_For_Comment ON C_Inner.PostId = P_For_Comment.Id
         WHERE C_Inner.UserId = U.Id
           AND C_Inner.CreationDate > B.Date
           AND B.Class = 1 -- Only for Gold badges
           AND P_For_Comment.OwnerUserId IS NOT NULL
           AND P_For_Comment.OwnerUserId <> U.Id
        ) AS CommentsOnOthersPostsAfterGoldBadge
    FROM Users AS U
    JOIN Badges AS B ON U.Id = B.UserId
    WHERE B.Class IN (1, 2) -- Focus on Gold or Silver badges
),
DeletedThenUndeletedPosts AS (
    -- CTE 7: Identifies posts that were deleted and subsequently undeleted.
    -- Calculates the duration a post spent in a deleted state.
    SELECT
        PH_Del.PostId,
        MIN(PH_Del.CreationDate) AS DeletionDate,
        MAX(PH_Undel.CreationDate) AS UndeletionDate,
        COUNT(DISTINCT PH_Del.UserId) AS UniqueDeletionVoters,
        COUNT(DISTINCT PH_Undel.UserId) AS UniqueUndeletionVoters,
        EXTRACT(EPOCH FROM (MAX(PH_Undel.CreationDate) - MIN(PH_Del.CreationDate))) / 86400 AS DaysBetweenDeletionUndeletion
    FROM PostHistory AS PH_Del
    JOIN PostHistory AS PH_Undel ON PH_Del.PostId = PH_Undel.PostId
    WHERE PH_Del.PostHistoryTypeId = 12 -- Post Deleted
      AND PH_Undel.PostHistoryTypeId = 13 -- Post Undeleted
      AND PH_Undel.CreationDate > PH_Del.CreationDate
    GROUP BY PH_Del.PostId
)
-- Main Query: Integrates insights from all CTEs to profile highly engaged and influential users.
SELECT
    CUS.UserId,
    CUS.DisplayName,
    CUS.Reputation,
    CUS.TotalPosts,
    CUS.TotalQuestions,
    CUS.TotalAnswers,
    CUS.TotalComments,
    COALESCE(CUS.AvgPostScore, 0.0) AS AvgPostScore,
    CUS.TotalUpvotesReceived,
    CUS.TotalDownvotesReceived,
    CUS.TotalBadges,
    CUS.UserEngagementScore,
    -- Aggregated metrics from RevisionAndCloseHistory for user's own posts
    COALESCE(SUM(RCH.TotalEdits) FILTER (WHERE P.OwnerUserId = CUS.UserId), 0) AS TotalEditsOnOwnPosts,
    COALESCE(SUM(RCH.TotalCloseEvents) FILTER (WHERE P.OwnerUserId = CUS.UserId), 0) AS TotalClosesOnOwnPosts,
    COALESCE(AVG(RCH.HoursToFirstEdit) FILTER (WHERE P.OwnerUserId = CUS.UserId), 0) AS AvgHoursToFirstEditOnOwnPosts,
    -- Aggregates distinct close reasons across all posts owned by the user.
    STRING_AGG(DISTINCT RCH.DistinctCloseReasons, '; ') FILTER (WHERE P.OwnerUserId = CUS.UserId AND RCH.DistinctCloseReasons IS NOT NULL) AS AllCloseReasonsForOwnPosts,
    -- Gathers relevant 'hot' tags for the user's questions, along with their 'Hotness Index'.
    STRING_AGG(DISTINCT TAS.TagName || ' (Hotness: ' || TAS.TagHotnessIndex || ')', ', ') FILTER (
        WHERE P.OwnerUserId = CUS.UserId
          AND P.PostTypeId = 1
          AND P.Tags IS NOT NULL
          AND EXISTS (SELECT 1 FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS PostTag WHERE PostTag = TAS.TagName)
    ) AS RelevantHotTagsForUser,
    -- Insights from AdvancedUserBadgeStats for Gold badge holders
    MAX(CASE WHEN AUBS.BadgeClass = 1 THEN AUBS.BadgeAwardDate ELSE NULL END) AS LastGoldBadgeDate,
    COALESCE(MAX(CASE WHEN AUBS.BadgeClass = 1 THEN AUBS.AvgPreBadgePostScore ELSE NULL END), 0.0) AS AvgPreGoldBadgePostScore,
    COALESCE(MAX(CASE WHEN AUBS.BadgeClass = 1 THEN AUBS.CommentsOnOthersPostsAfterGoldBadge ELSE NULL END), 0) AS CommentsOnOthersPostsAfterGoldBadge,
    -- Counts the number of the user's posts that link to highly favorited questions by other users.
    COALESCE(COUNT(DISTINCT PL.PostId) FILTER (
        WHERE PL.LinkTypeId = 1 -- Linked type
          AND P_Linked.FavoriteCount >= 100 -- Target post is highly favorited
          AND P_Linked.OwnerUserId IS NOT NULL
          AND P_Linked.OwnerUserId <> CUS.UserId -- Target post owned by another user
          AND P_Linked.PostTypeId = 1 -- Target post is a question
    ), 0) AS LinkedToHighFavoriteForeignPosts,
    -- Counts the user's posts that were deleted and then undeleted.
    COALESCE(COUNT(DISTINCT DTUP.PostId) FILTER (WHERE P.OwnerUserId = CUS.UserId), 0) AS OwnPostsDeletedThenUndeletedCount,
    -- Calculates the average number of days the user's posts spent deleted.
    COALESCE(AVG(DTUP.DaysBetweenDeletionUndeletion) FILTER (WHERE P.OwnerUserId = CUS.UserId), 0.0) AS AvgDaysOwnPostsDeleted
FROM CorrectedUserContributionSummary AS CUS
LEFT JOIN Posts AS P ON CUS.UserId = P.OwnerUserId -- Join for post-specific aggregations for the current user
LEFT JOIN RevisionAndCloseHistory AS RCH ON P.Id = RCH.PostId
LEFT JOIN TagAggregateStats AS TAS ON TRUE -- Logical join, conditions are in the SELECT clause (for filtering related tags)
LEFT JOIN AdvancedUserBadgeStats AS AUBS ON CUS.UserId = AUBS.UserId
LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId -- User's post (P.Id) contains a link
LEFT JOIN Posts AS P_Linked ON PL.RelatedPostId = P_Linked.Id -- The post that is linked to by the user's post
LEFT JOIN DeletedThenUndeletedPosts AS DTUP ON P.Id = DTUP.PostId
WHERE
    CUS.TotalPosts > 100 -- Filter for sufficiently active users
    AND CUS.Reputation > 1000 -- Filter for reputable users
    AND CUS.LastAccessDate > NOW() - INTERVAL '1 year' -- Filter for recently active users
    -- Ensure the user has at least one question relevant to the 'hot' tags defined in TagAggregateStats.
    AND EXISTS (
        SELECT 1
        FROM Posts AS P_Inner
        WHERE P_Inner.OwnerUserId = CUS.UserId
          AND P_Inner.PostTypeId = 1
          AND P_Inner.Tags IS NOT NULL
          AND EXISTS (SELECT 1 FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(P_Inner.Tags FROM 2 FOR LENGTH(P_Inner.Tags) - 2), '><')) AS PostTag WHERE PostTag IN ('sql', 'database', 'performance', 'indexing', 'query-optimization', 'postgresql', 'mysql', 'mssql', 'optimization', 'bigdata', 'nosql', 'json', 'data-modeling', 'etl'))
    )
GROUP BY
    CUS.UserId, CUS.DisplayName, CUS.Reputation, CUS.TotalPosts, CUS.TotalQuestions,
    CUS.TotalAnswers, CUS.TotalComments, CUS.AvgPostScore, CUS.TotalUpvotesReceived,
    CUS.TotalDownvotesReceived, CUS.TotalBadges, CUS.UserEngagementScore, CUS.UserCreationDate, CUS.LastAccessDate
HAVING
    -- Additional filtering based on aggregated values to identify highly engaged users
    COALESCE(SUM(RCH.TotalEdits) FILTER (WHERE P.OwnerUserId = CUS.UserId), 0) > 5 OR
    COALESCE(SUM(RCH.TotalCloseEvents) FILTER (WHERE P.OwnerUserId = CUS.UserId), 0) > 1 OR
    MAX(CUS.TotalBadges) > 3 OR
    COALESCE(MAX(CASE WHEN AUBS.BadgeClass = 1 THEN AUBS.CommentsOnOthersPostsAfterGoldBadge ELSE NULL END), 0) > 10
ORDER BY
    CUS.UserEngagementScore DESC, CUS.Reputation DESC, CUS.TotalPosts DESC
LIMIT 100;
