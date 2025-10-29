-- {"query": "1073.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2812} 

WITH ParsedPostTags AS (
    -- Extract and unnest tags from question posts
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS TagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL
      AND LENGTH(P.Tags) > 2
      AND P.PostTypeId = 1 -- Only questions have tags in this format
),
PostCommentEditAggregates AS (
    -- Aggregate comments and edit history for posts
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.AcceptedAnswerId,
        COALESCE(P.CommunityOwnedDate, '1900-01-01') AS CommunityOwnedDate,
        COALESCE(P.ParentId, -1) AS ParentPostId, -- Use -1 for questions, real parent id for answers
        COUNT(DISTINCT C.Id) AS TotalCommentsOnPost,
        MAX(C.CreationDate) AS LatestCommentDateOnPost,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS TotalEditRevisions, -- Edits for Title, Body, Tags, Rollback Body, Rollback Tags
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS LatestEditDate
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.ClosedDate, P.AcceptedAnswerId, P.CommunityOwnedDate, P.ParentId
),
PostTagsAndLinks AS (
    -- Aggregate tags and linked/duplicate post counts for each post
    SELECT
        PCA.PostId,
        STRING_AGG(DISTINCT PPT.TagName, '$$$') FILTER (WHERE PPT.TagName IS NOT NULL) AS AssociatedTagsString,
        COUNT(DISTINCT PL_Linked.RelatedPostId) FILTER (WHERE PL_Linked.LinkTypeId = 1) AS CountLinkedToPosts,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) FILTER (WHERE PL_Duplicate.LinkTypeId = 3) AS CountDuplicateOfPosts
    FROM PostCommentEditAggregates PCA
    LEFT JOIN ParsedPostTags PPT ON PCA.PostId = PPT.PostId
    LEFT JOIN PostLinks PL_Linked ON PCA.PostId = PL_Linked.PostId
    LEFT JOIN PostLinks PL_Duplicate ON PCA.PostId = PL_Duplicate.PostId
    GROUP BY PCA.PostId
),
CombinedPostMetrics AS (
    -- Combine post details with tag/link aggregates and calculate various post-level metrics
    SELECT
        PCA.PostId,
        PCA.OwnerUserId,
        PCA.PostTypeId,
        PCA.PostCreationDate,
        PCA.PostScore,
        PCA.PostViewCount,
        PCA.AnswerCount,
        PCA.FavoriteCount,
        PCA.ClosedDate,
        PCA.AcceptedAnswerId,
        PCA.CommunityOwnedDate,
        PCA.ParentPostId,
        PCA.TotalCommentsOnPost,
        PCA.LatestCommentDateOnPost,
        PCA.TotalEditRevisions,
        PCA.LatestEditDate,
        PTL.AssociatedTagsString,
        PTL.CountLinkedToPosts,
        PTL.CountDuplicateOfPosts,
        -- Complex Post Engagement Score calculation
        (PCA.PostScore * 0.5 + PCA.PostViewCount * 0.01 + PCA.TotalCommentsOnPost * 2 + COALESCE(PCA.FavoriteCount, 0) * 5 + COALESCE(PCA.AnswerCount, 0) * 3 + PCA.TotalEditRevisions * -1) AS PostEngagementScore,
        CASE
            WHEN PCA.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN PCA.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswer'
            WHEN PCA.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'OpenNoAnswers'
        END AS DerivedPostStatus,
        AGE(NOW(), PCA.CreationDate) AS PostAgeInterval, -- Date arithmetic
        -- Correlated subquery: Average score of answers for a question
        (SELECT AVG(A.Score) FROM Posts A WHERE A.ParentId = PCA.PostId AND PCA.PostTypeId = 1) AS AvgAnswerScoreForQuestion
    FROM PostCommentEditAggregates PCA
    LEFT JOIN PostTagsAndLinks PTL ON PCA.PostId = PTL.PostId
),
UserOverallMetrics AS (
    -- Aggregate post metrics to the user level and calculate user-specific metrics
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUserUpvotesGiven,
        U.DownVotes AS TotalUserDownvotesGiven,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        CASE WHEN U.WebsiteUrl IS NOT NULL THEN TRUE ELSE FALSE END AS HasWebsite,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        MAX(B.Date) AS LatestBadgeDate,
        COUNT(DISTINCT CASE WHEN CPM.PostTypeId = 1 THEN CPM.PostId END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN CPM.PostTypeId = 2 THEN CPM.PostId END) AS TotalAnswersProvided,
        COUNT(DISTINCT CPM.PostId) AS TotalPostsContributed,
        COALESCE(SUM(CPM.PostScore), 0) AS TotalPostsScore,
        COALESCE(SUM(CPM.PostViewCount), 0) AS TotalPostsViewCount,
        COALESCE(SUM(CPM.FavoriteCount), 0) AS TotalPostsFavoriteCount,
        COALESCE(SUM(CPM.TotalCommentsOnPost), 0) AS TotalCommentsOnOwnPosts,
        COALESCE(AVG(CPM.PostEngagementScore), 0.0) AS AvgPostEngagementScore,
        COALESCE(AVG(NULLIF(CASE WHEN CPM.PostTypeId = 1 THEN CPM.AnswerCount END, 0)), 0.0) AS AvgAnswersPerQuestion,
        -- Conditional calculation for Question Acceptance Rate
        COALESCE(CAST(SUM(CASE WHEN CPM.PostTypeId = 1 AND CPM.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN CPM.PostTypeId = 1 THEN 1 ELSE 0 END), 0), 0.0) AS QuestionAcceptanceRate,
        -- Conditional calculation for Answer Acceptance Rate, requires join to parent post
        COALESCE(CAST(SUM(CASE WHEN CPM.PostTypeId = 2 AND P_PARENT.AcceptedAnswerId = CPM.PostId THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN CPM.PostTypeId = 2 THEN 1 ELSE 0 END), 0), 0.0) AS AnswerAcceptanceRate,
        MAX(CPM.LatestEditDate) AS LatestContentEditDate,
        SUM(CASE WHEN CPM.DerivedPostStatus = 'Closed' THEN 1 ELSE 0 END) AS ClosedPostsCount,
        STRING_AGG(DISTINCT LEFT(CPM.AssociatedTagsString, 50) || '...', ' | ') FILTER (WHERE CPM.AssociatedTagsString IS NOT NULL AND CPM.AssociatedTagsString != '') AS TopTagsExcerpt, -- String expression
        -- Window functions: FIRST_VALUE to get details of top-scoring post
        FIRST_VALUE(CPM.PostId) OVER (PARTITION BY U.Id ORDER BY CPM.PostScore DESC, CPM.PostCreationDate DESC) AS TopScoringPostId,
        FIRST_VALUE(CPM.PostScore) OVER (PARTITION BY U.Id ORDER BY CPM.PostScore DESC, CPM.PostCreationDate DESC) AS TopScoringPostScore,
        -- Non-correlated subquery: Average reputation of users created around the same time
        (SELECT AVG(U2.Reputation) FROM Users U2 WHERE U2.CreationDate BETWEEN U.CreationDate - INTERVAL '6 months' AND U.CreationDate + INTERVAL '6 months') AS AvgReputationOfContemporaries
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN CombinedPostMetrics CPM ON U.Id = CPM.OwnerUserId
    LEFT JOIN Posts P_PARENT ON CPM.ParentPostId = P_PARENT.Id -- Join to get AcceptedAnswerId for parent question
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.Location, U.WebsiteUrl
),
FinalUserRanking AS (
    -- Apply ranking and advanced categorization to user metrics
    SELECT
        UOM.UserId,
        UOM.DisplayName,
        UOM.Reputation,
        UOM.UserLocation,
        UOM.TotalBadges,
        UOM.GoldBadges,
        UOM.TotalQuestionsAsked,
        UOM.TotalAnswersProvided,
        UOM.TotalPostsContributed,
        UOM.TotalPostsScore,
        UOM.AvgPostEngagementScore,
        UOM.QuestionAcceptanceRate,
        UOM.AnswerAcceptanceRate,
        UOM.ClosedPostsCount,
        NULLIF(UOM.TopTagsExcerpt, '...') AS TopTagsSummary, -- NULLIF example for cleanup
        UOM.TopScoringPostId,
        UOM.TopScoringPostScore,
        UOM.AvgReputationOfContemporaries,
        -- Window functions for ranking and comparison
        RANK() OVER (ORDER BY UOM.Reputation DESC, UOM.TotalPostsScore DESC, UOM.AvgPostEngagementScore DESC, UOM.AnswerAcceptanceRate DESC) AS OverallUserRank,
        NTILE(5) OVER (ORDER BY UOM.Reputation DESC) AS ReputationQuintile,
        LAG(UOM.DisplayName, 1, '---') OVER (ORDER BY UOM.Reputation DESC) AS PreviousRankedUser,
        LEAD(UOM.DisplayName, 1, '---') OVER (ORDER BY UOM.Reputation DESC) AS NextRankedUser,
        -- String expression with LPAD and concatenation
        COALESCE(UPPER(LEFT(UOM.DisplayName, 1)), '?') || '-' || COALESCE(UOM.UserLocation, 'UNKNOWN') || '-' || LPAD(UOM.UserId::TEXT, 8, '0') AS UserIdentifierString,
        -- Complicated conditional logic for user tier classification
        CASE
            WHEN UOM.Reputation >= 10000 AND UOM.GoldBadges >= 5 THEN 'Legendary Contributor'
            WHEN UOM.Reputation >= 5000 OR UOM.TotalPostsContributed >= 500 THEN 'Prodigious Contributor'
            WHEN UOM.Reputation >= 1000 AND UOM.TotalPostsScore >= 1000 AND UOM.QuestionAcceptanceRate >= 0.5 THEN 'Active & Effective Contributor'
            WHEN UOM.TotalPostsContributed > 100 AND UOM.TotalPostsScore > 500 AND UOM.AnswerAcceptanceRate > 0.6 THEN 'Specialized Answerer'
            ELSE 'Casual User'
        END AS UserContributionTier
    FROM UserOverallMetrics UOM
    WHERE UOM.TotalPostsContributed > 10 -- Filter for active users
      AND UOM.Reputation