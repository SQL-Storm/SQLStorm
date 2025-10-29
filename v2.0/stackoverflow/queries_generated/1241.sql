-- {"query": "1241.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3710} 

WITH UserBaseMetrics AS (
    -- CTE 1: Gathers foundational user metrics and activity counts, including creation and last access dates.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
        COALESCE(SUM(P.Score), 0) AS TotalPostsScore,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views
),
PostDetailedAnalytics AS (
    -- CTE 2: Provides detailed post metrics including window functions and correlated subqueries for questions and answers.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Score AS PostScore,
        COALESCE(P.ViewCount, 0) AS ViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.Title,
        P.Tags,
        -- Window function: Rank posts by score and views within a user's contributions.
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, COALESCE(P.ViewCount, 0) DESC) AS PostRankByScoreViews,
        -- Window function: Calculate the time difference (in hours) to the user's previous post.
        EXTRACT(EPOCH FROM (P.CreationDate - LAG(P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate))) / 3600 AS HoursSincePrevPost,
        -- Correlated subquery: Fetches the first 100 characters of the latest comment for each post.
        (
            SELECT SUBSTRING(C.Text, 1, 100)
            FROM Comments C
            WHERE C.PostId = P.Id
            ORDER BY C.CreationDate DESC
            LIMIT 1
        ) AS LatestCommentSnippet,
        -- Complex CASE statement to categorize post status.
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 'AnswerAccepted'
            WHEN P.PostTypeId = 1 AND COALESCE(P.AnswerCount, 0) > 0 THEN 'Answered'
            WHEN P.LastActivityDate > NOW() - INTERVAL '3 months' THEN 'RecentlyActive'
            ELSE 'Dormant'
        END AS PostStatus
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2).
),
UserTagPerformance AS (
    -- CTE 3: Analyzes user's engagement and performance with specific tags derived from their posts.
    SELECT
        PDA.OwnerUserId AS UserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(PDA.Tags, 2, LENGTH(PDA.Tags)-2), '><'))) AS TagName,
        COUNT(PDA.PostId) AS TaggedPostsCount,
        SUM(PDA.PostScore) AS TaggedPostsTotalScore,
        AVG(PDA.PostScore) AS TaggedPostsAvgScore,
        -- Window function: Ranks tags for each user based on post count and total score.
        RANK() OVER (PARTITION BY PDA.OwnerUserId ORDER BY COUNT(PDA.PostId) DESC, SUM(PDA.PostScore) DESC) AS TagRank
    FROM PostDetailedAnalytics PDA
    WHERE PDA.Tags IS NOT NULL AND LENGTH(PDA.Tags) > 2 -- Ensure the tags string is valid for splitting.
    GROUP BY PDA.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(PDA.Tags, 2, LENGTH(PDA.Tags)-2), '><')))
),
PostLifecycleEvents AS (
    -- CTE 4: Tracks significant post history events, including closures, deletions, and migrations.
    SELECT
        PH.PostId,
        PH.UserId AS EventInitiatorUserId,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryEventName,
        PH.CreationDate AS EventDate,
        PH.Comment,
        -- Extracts the close reason name from the comment field if applicable.
        COALESCE(CR.Name, 'N/A') AS ExtractedCloseReason,
        -- Window function: Identifies the previous event type for a post, useful for sequences like close -> reopen.
        LAG(PH.PostHistoryTypeId, 1, 0) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEventType,
        -- Window function: Counts specific event types per post.
        COUNT(PH.Id) OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId) AS EventTypeCountPerPost,
        -- Window function: Sums problematic events (closed or deleted) for each post.
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS ProblemEventCount
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$' AND PH.Comment::smallint = CR.Id
    WHERE PH.PostHistoryTypeId IN (
        1, 2, 3, 4, 5, 6, -- Initial/Edit Title, Body, Tags
        10, 11, 12, 13, -- Post Closed, Reopened, Deleted, Undeleted
        16, -- Community Owned
        35, 36 -- Post Migrated Away/Here
    )
),
UserBadgeImpact AS (
    -- CTE 5: Identifies a user's most significant (highest class) badge.
    SELECT
        B.UserId,
        B.Name AS BadgeName,
        B.Class,
        -- Window function: Ranks badges for each user by class (Gold=1, Silver=2, Bronze=3) and then date.
        ROW_NUMBER() OVER (PARTITION BY B.UserId ORDER BY B.Class ASC, B.Date DESC) AS BadgeRank
    FROM Badges B
    WHERE B.Class IN (1, 2) -- Only considering Gold (1) or Silver (2) badges as significant.
)
-- Main Query: Synthesizes information from all CTEs to identify influential users with complex activity patterns.
SELECT
    UBM.UserId,
    UBM.DisplayName,
    UBM.Reputation,
    UBM.TotalPosts,
    UBM.QuestionsCount,
    UBM.AnswersCount,
    UBM.AvgPostScore,
    UBM.TotalComments,
    UBM.TotalUpvotesGiven,
    UBM.UserProfileViews,
    AGE(NOW(), UBM.UserCreationDate) AS AccountAge, -- Calculation: User account age using date functions.
    COALESCE(MAX(CASE WHEN PDA.PostRankByScoreViews = 1 AND PDA.PostTypeId = 1 THEN PDA.Title ELSE NULL END), 'No Top Question') AS TopQuestionTitle,
    COALESCE(MAX(CASE WHEN PDA.PostRankByScoreViews = 1 AND PDA.PostTypeId = 2 THEN PDA.Title ELSE NULL END), 'No Top Answer') AS TopAnswerTitle,
    SUM(CASE WHEN PDA.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS UserClosedPosts,
    COUNT(DISTINCT PDA.PostId) FILTER (WHERE PDA.PostStatus = 'AnswerAccepted') AS UserAcceptedAnsweredQuestions,
    MAX(UTP.TagName) FILTER (WHERE UTP.TagRank = 1) AS MostDominantTag,
    MAX(UTP.TaggedPostsTotalScore) FILTER (WHERE UTP.TagRank = 1) AS MostDominantTagScore,
    COALESCE(MAX(UBI.BadgeName), 'No Significant Badge') AS HighestRankBadge, -- NULL logic: provides default if no significant badge.
    SUM(CASE WHEN PLE.HistoryEventName = 'Post Closed' AND PLE.EventInitiatorUserId IS DISTINCT FROM UBM.UserId THEN 1 ELSE 0 END) AS PostsClosedByOthers, -- Predicate: Event initiated by someone else.
    SUM(CASE WHEN PLE.HistoryEventName = 'Post Deleted' AND PLE.EventInitiatorUserId IS DISTINCT FROM UBM.UserId THEN 1 ELSE 0 END) AS PostsDeletedByOthers,
    -- Correlated Subquery: Counts recent comments on the user's posts from high-reputation users.
    (
        SELECT
            COUNT(DISTINCT C_Sub.Id)
        FROM Comments C_Sub
        JOIN Users U_Sub ON C_Sub.UserId = U_Sub.Id
        WHERE C_Sub.PostId IN (SELECT PDA_Sub.PostId FROM PostDetailedAnalytics PDA_Sub WHERE PDA_Sub.OwnerUserId = UBM.UserId)
          AND U_Sub.Reputation > 5000
          AND C_Sub.CreationDate > NOW() - INTERVAL '6 months'
    ) AS HighRepUserCommentsCount,
    -- Complicated Calculation: An "Influence Score" blending various activity metrics, with division by NULLIF to prevent errors.
    (UBM.TotalPostsScore * 0.4 + UBM.TotalComments * 0.2 + UBM.TotalUpvotesGiven * 0.1 + UBM.UserProfileViews * 0.05) /
    (NULLIF(UBM.TotalPosts + UBM.TotalComments + 1, 0)) AS InfluenceScore,
    -- String Expression: Concatenates user's display name with their most dominant tag for a unique identifier.
    UBM.DisplayName || ' (' || COALESCE(MAX(UTP.TagName) FILTER (WHERE UTP.TagRank = 1), 'N/A') || ')' AS UserTagIdentifier,
    -- EXISTS condition: Checks if the user has any posts that are linked as duplicates.
    EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId IN (SELECT PDA_Sub.PostId FROM PostDetailedAnalytics PDA_Sub WHERE PDA_Sub.OwnerUserId = UBM.UserId)
          AND PL.LinkTypeId = 3 -- LinkType 3 typically indicates a duplicate.
    ) AS HasDuplicatePosts
FROM UserBaseMetrics UBM
LEFT JOIN PostDetailedAnalytics PDA ON UBM.UserId = PDA.OwnerUserId
LEFT JOIN UserTagPerformance UTP ON UBM.UserId = UTP.UserId AND UTP.TagRank = 1 -- Join only the user's most dominant tag.
LEFT JOIN PostLifecycleEvents PLE ON PDA.PostId = PLE.PostId
LEFT JOIN UserBadgeImpact UBI ON UBM.UserId = UBI.UserId AND UBI.BadgeRank = 1 -- Join only the user's highest-ranked badge.
WHERE UBM.Reputation > 2000
  AND UBM.TotalPosts >= 10
  AND UBM.LastAccessDate > NOW() - INTERVAL '1 year' -- Predicate: Users active within the last year.
  AND UBM.DisplayName IS NOT NULL
  AND UBM.DisplayName LIKE 'S%' -- String Expression: Filter display names starting with 'S'.
  AND UBM.UserCreationDate BETWEEN '2015-01-01' AND '2020-01-01' -- Predicate: Specific account creation date range.
  AND NOT EXISTS ( -- NOT EXISTS condition: Exclude users with recent questions that have no comments.
        SELECT 1 FROM Posts P_NoComments
        WHERE P_NoComments.OwnerUserId = UBM.UserId
          AND P_NoComments.CommentCount = 0
          AND P_NoComments.PostTypeId = 1
          AND P_NoComments.CreationDate > NOW() - INTERVAL '2 years'
    )
GROUP BY UBM.UserId, UBM.DisplayName, UBM.Reputation, UBM.TotalPosts, UBM.QuestionsCount, UBM.AnswersCount, UBM.AvgPostScore, UBM.TotalComments, UBM.TotalUpvotesGiven, UBM.UserProfileViews, UBM.UserCreationDate
HAVING SUM(CASE WHEN PDA.PostStatus = 'Closed' THEN 1 ELSE 0 END) < 3 -- Predicate: Users with less than 3 closed posts.
   AND COUNT(DISTINCT CASE WHEN PDA.ViewCount > 1000 THEN PDA.PostId ELSE NULL END) >= 1 -- Predicate: At least one post with over 1000 views.

UNION ALL -- Set Operator: Combines the above result with a second, distinct set of users.

-- Second part of UNION ALL: Focuses on users who frequently answer highly viewed questions.
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    COUNT(P.Id) AS TotalPosts,
    0 AS QuestionsCount, -- Placeholder for this part of the union.
    COUNT(P.Id) AS AnswersCount,
    COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
    COUNT(C.Id) AS TotalComments,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
    U.Views AS UserProfileViews,
    AGE(NOW(), U.CreationDate) AS AccountAge,
    NULL AS TopQuestionTitle,
    NULL AS TopAnswerTitle,
    0 AS UserClosedPosts,
    0 AS UserAcceptedAnsweredQuestions,
    'HighlyViewedAnswerer' AS MostDominantTag, -- Placeholder tag for this group.
    0 AS MostDominantTagScore,
    'Bronze Contributor' AS HighestRankBadge, -- Placeholder badge for this group.
    0 AS PostsClosedByOthers,
    0 AS PostsDeletedByOthers,
    0 AS HighRepUserCommentsCount,
    0.0 AS InfluenceScore, -- Placeholder score.
    U.DisplayName || ' (HV-Answerer)' AS UserTagIdentifier, -- String expression for identification.
    FALSE AS HasDuplicatePosts
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 2 -- Only answers.
JOIN Posts Q ON P.ParentId = Q.Id AND Q.ViewCount > 5000 -- Parent question must be highly viewed.
LEFT JOIN Comments C ON U.Id = C.UserId
LEFT JOIN Votes V ON U.Id = V.UserId
WHERE U.Reputation > 1000
  AND P.CreationDate > NOW() - INTERVAL '2 years' -- Predicate: Recent answers.
GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.CreationDate
HAVING COUNT(P.Id) >= 5 -- Predicate: At least 5 answers to highly viewed questions.

ORDER BY Reputation DESC, InfluenceScore DESC NULLS LAST, AccountAge DESC
LIMIT 500; -- Limits the final combined result set.
