-- {"query": "1995.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3218} 

WITH UserEngagementSummary AS (
    -- Aggregate user-level statistics including post, comment, and vote counts, and badge distribution.
    -- This CTE uses LEFT JOINs to ensure all users are included, even those with no activity in certain categories.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPosts,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScoreByOwner,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MIN(P.CreationDate) AS FirstPostCreationDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailedMetrics AS (
    -- Calculates comprehensive metrics for each post, integrating post history, comment scores,
    -- and using window functions for ranking and temporal analysis (previous/next post dates).
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        COALESCE(P.FavoriteCount, 0) AS EffectiveFavoriteCount, -- Handles NULL FavoriteCount with COALESCE
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title,
        P.Tags,
        P.ClosedDate,
        (
            -- Correlated subquery to calculate average comment score for the current post.
            SELECT COALESCE(AVG(InnerC.Score), 0.0)
            FROM Comments InnerC
            WHERE InnerC.PostId = P.Id
        ) AS AvgCommentScoreForPost,
        COALESCE(COUNT(DISTINCT PH.Id), 0) AS TotalHistoryEvents,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END), 0) AS EditCount, -- Count of title/body/tag edits
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        -- Window functions to rank posts within their PostType by score and creation date.
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostRankInType,
        -- Window functions to find the creation date of the previous and next post by the same owner.
        LAG(P.CreationDate, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostCreationDate,
        LEAD(P.CreationDate, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextPostCreationDate
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount,
             P.OwnerUserId, P.AcceptedAnswerId, P.ParentId, P.Title, P.Tags, P.ClosedDate
),
QuestionAnswerContent AS (
    -- Uses a set operator (UNION ALL) to combine questions and answers into a unified content stream,
    -- distinguishing between their specific attributes (e.g., ViewCount for questions, ParentId for answers).
    SELECT
        PDM.PostId,
        PDM.PostTypeId,
        PDM.PostCreationDate,
        PDM.OwnerUserId,
        PDM.PostScore,
        PDM.ViewCount,
        PDM.EffectiveFavoriteCount,
        PDM.Title,
        PDM.Tags,
        PDM.AcceptedAnswerId,
        NULL::INT AS ParentQuestionId, -- For questions, parent is null
        PDM.AvgCommentScoreForPost,
        PDM.PostRankInType,
        PDM.PrevPostCreationDate,
        PDM.NextPostCreationDate
    FROM PostDetailedMetrics PDM
    WHERE PDM.PostTypeId = 1 -- Questions
    UNION ALL
    SELECT
        PDM.PostId,
        PDM.PostTypeId,
        PDM.PostCreationDate,
        PDM.OwnerUserId,
        PDM.PostScore,
        NULL AS ViewCount, -- Answers don't have ViewCount directly
        NULL AS EffectiveFavoriteCount, -- Answers usually don't have FavoriteCount directly in Posts table
        NULL AS Title, -- Answers don't have titles directly
        NULL AS Tags, -- Answers don't have tags directly
        NULL AS AcceptedAnswerId, -- Answers cannot accept other answers
        PDM.ParentId AS ParentQuestionId, -- Parent for an answer is a question
        PDM.AvgCommentScoreForPost,
        PDM.PostRankInType,
        PDM.PrevPostCreationDate,
        PDM.NextPostCreationDate
    FROM PostDetailedMetrics PDM
    WHERE PDM.PostTypeId = 2 -- Answers
),
TagAnalysis AS (
    -- Analyzes the popularity and performance of individual tags across questions.
    -- Uses string_to_array and unnest for tag parsing, then DENSE_RANK for popularity.
    SELECT
        TagName,
        COUNT(DISTINCT P.Id) AS TotalPostsWithTag,
        COALESCE(AVG(P.Score), 0.0) AS AvgScoreOfPostsWithTag,
        COALESCE(MAX(P.ViewCount), 0) AS MaxViewCountForTag,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT P.Id) DESC, COALESCE(AVG(P.Score), 0.0) DESC) AS TagPopularityRank
    FROM Posts P,
    LATERAL (SELECT unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName) AS TaggedPosts
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.Tags != ''
    GROUP BY TagName
)
-- Main query: Joins all CTEs and PostHistory for closed post details, applies complex predicates,
-- calculations, string expressions, and NULL logic.
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.TotalQuestions,
    UES.TotalAnswers,
    QAC.PostId AS ContentPostId,
    QAC.PostTypeId,
    QAC.Title AS ContentTitle,
    QAC.PostScore AS ContentScore,
    QAC.ViewCount AS ContentViewCount,
    QAC.EffectiveFavoriteCount AS ContentFavoriteCount,
    QAC.AvgCommentScoreForPost AS ContentAvgCommentScore,
    QAC.PostRankInType,
    QAC.PrevPostCreationDate,
    QAC.NextPostCreationDate,
    -- Calculation: Time in hours between consecutive posts by a user.
    EXTRACT(EPOCH FROM (QAC.NextPostCreationDate - QAC.PostCreationDate)) / 3600.0 AS HoursUntilNextPost,
    -- Calculation: Net votes given by the user.
    (UES.TotalUpvotesGiven - UES.TotalDownvotesGiven) AS NetVotesGiven,
    (
        -- Correlated subquery: Calculates the average score of previous posts of the same type by the same owner.
        SELECT COALESCE(AVG(InnerP.Score), 0.0)
        FROM Posts InnerP
        WHERE InnerP.OwnerUserId = UES.UserId
          AND InnerP.PostTypeId = QAC.PostTypeId
          AND InnerP.CreationDate < QAC.PostCreationDate
          AND InnerP.CreationDate >= UES.FirstPostCreationDate
    ) AS AvgScoreOfPrevPostsByType,
    -- Complicated expression with conditional logic: Assigns a user tier based on reputation and badges.
    CASE
        WHEN UES.Reputation > 10000 AND UES.GoldBadges >= 5 THEN 'Veteran Elite'
        WHEN UES.Reputation > 5000 AND UES.SilverBadges >= 3 THEN 'Experienced Contributor'
        WHEN UES.Reputation > 1000 AND UES.BronzeBadges >= 10 THEN 'Active Member'
        WHEN UES.Reputation > 100 THEN 'New Contributor'
        ELSE 'Casual User'
    END AS UserTier,
    PDM_OrigQ.Title AS OriginalQuestionTitleForAnswer, -- Outer Join to get original question title for answers
    COALESCE(PDM_AcceptedA.PostScore, 0) AS AcceptedAnswerScore, -- NULL logic: Score of accepted answer, default to 0.
    -- String expression: Creates a hash-like prefix from display name and user ID.
    LOWER(LEFT(UES.DisplayName, 3)) || '-' || (UES.UserId % 1000 + 1) AS UserHashPrefix,
    PH_Closed.Comment AS CloseReasonName, -- Join to PostHistory for the close reason comment
    CASE WHEN PDM_Closed.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosedContent,
    -- NULL logic and calculation: Days from post creation to closure.
    EXTRACT(DAY FROM (PDM_Closed.ClosedDate - PDM_Closed.PostCreationDate)) AS DaysToClose,
    TopTaggedContent.TagName AS TopRelatedTagName, -- Top tag for this specific piece of content based on global popularity
    TopTaggedContent.TagPopularityRank AS TopRelatedTagRank
FROM UserEngagementSummary UES
LEFT JOIN QuestionAnswerContent QAC ON UES.UserId = QAC.OwnerUserId
LEFT JOIN PostDetailedMetrics PDM_OrigQ ON QAC.ParentQuestionId = PDM_OrigQ.PostId -- Details of the parent question for answers
LEFT JOIN PostDetailedMetrics PDM_AcceptedA ON QAC.AcceptedAnswerId = PDM_AcceptedA.PostId -- Details of the accepted answer for questions
LEFT JOIN PostDetailedMetrics PDM_Closed ON QAC.PostId = PDM_Closed.PostId AND PDM_Closed.ClosedDate IS NOT NULL
LEFT JOIN PostHistory PH_Closed ON PDM_Closed.PostId = PH_Closed.PostId
    AND PH_Closed.PostHistoryTypeId = 10 -- Only consider 'Post Closed' events
    AND PDM_Closed.ClosedDate = PH_Closed.CreationDate -- Match the exact closing event date
LEFT JOIN LATERAL (
    -- Lateral subquery to find the most popular tag (globally) associated with the current content's tags.
    -- This handles cases where a post has multiple tags and we want to pick one based on global rank.
    SELECT TA.TagName, TA.TagPopularityRank
    FROM TagAnalysis TA
    WHERE TA.TagName IN (
        SELECT unnest(string_to_array(substring(QAC.Tags, 2, length(QAC.Tags)-2), '><'))
        WHERE QAC.Tags IS NOT NULL
    )
    ORDER BY TA.TagPopularityRank ASC
    LIMIT 1
) AS TopTaggedContent ON QAC.Tags IS NOT NULL AND QAC.PostTypeId = 1 -- Only apply this to questions that have tags
WHERE
    UES.TotalPosts > 0 -- Ensure the user has at least one post.
    AND QAC.PostId IS NOT NULL -- Only include users with corresponding posts in QAC.
    AND (
        -- Complex predicate: Filters content by title/tag keywords or includes all answers.
        QAC.Title ILIKE '%sql%' OR QAC.Tags ILIKE '%<postgresql>%' OR QAC.Tags ILIKE '%<database>%' OR QAC.Tags ILIKE '%<query>%'
        OR QAC.PostTypeId = 2 -- Include all answers regardless of title/tag content.
    )
    AND QAC.PostCreationDate BETWEEN UES.UserCreationDate AND UES.LastAccessDate -- Post created within user's active period.
    AND (PDM_Closed.ClosedDate IS NULL OR PDM_Closed.ClosedDate < NOW() - INTERVAL '30 days') -- Exclude recently closed posts.
    AND QAC.PostScore > (
        -- Complex predicate with a subquery using a window function: Filters posts with score above the 25th percentile for their post type.
        SELECT COALESCE(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Score) OVER (PARTITION BY PostTypeId), 0)
        FROM Posts
        WHERE PostTypeId = QAC.PostTypeId
    )
ORDER BY
    UES.Reputation DESC,
    QAC.PostCreationDate DESC,
    TopTaggedContent.TagPopularityRank ASC
LIMIT 1000;
