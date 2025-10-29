-- {"query": "1081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3680} 

WITH UserAggregates AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalOwnedPosts,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        MAX(B.Date) AS LatestBadgeDate,
        -- Correlated subquery: Total bounty given by user
        (SELECT COALESCE(SUM(V.BountyAmount), 0) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 8) AS TotalBountyProvided,
        CASE
            WHEN U.Reputation >= 100000 THEN 'Legendary'
            WHEN U.Reputation >= 25000 THEN 'Expert'
            WHEN U.Reputation >= 5000 THEN 'Advanced'
            WHEN U.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationTier,
        EXTRACT(EPOCH FROM (NOW() - U.LastAccessDate)) / 86400.0 AS DaysSinceLastAccess
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views
),
PostDetailsWithHistory AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.LastEditorUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS TotalPostComments,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.Body,
        P.AcceptedAnswerId,
        P.ParentId,
        P.ClosedDate,
        -- Correlated subqueries: specific vote types
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVotesReceived,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVotesReceived,
        -- Aggregated post history metrics
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title/Body/Tags edits
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS CloseHistoryCount,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)) AS LastCloseHistoryDate,
        -- Correlated subquery: most recent comment content
        (SELECT COALESCE(C_sub.Text, '') FROM Comments C_sub WHERE C_sub.PostId = P.Id ORDER BY C_sub.CreationDate DESC LIMIT 1) AS LatestCommentSnippet,
        -- Window function over comments for this post
        AVG(COALESCE(C.Score, 0)) OVER (PARTITION BY P.Id) AS AvgCommentScore,
        COUNT(DISTINCT PL.Id) AS TotalRelatedLinks,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicateLinkCount
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId -- Included for AvgCommentScore window function
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.LastEditorUserId, P.CreationDate, P.LastActivityDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags, P.Body, P.AcceptedAnswerId, P.ParentId, P.ClosedDate
),
ParsedPostTags AS (
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
HotTagsCategorization AS (
    SELECT
        PPT.TagName,
        COUNT(DISTINCT PPT.PostId) AS TaggedPostCount,
        SUM(PDH.ViewCount) AS TotalTaggedPostViews,
        AVG(PDH.PostScore) AS AvgTaggedPostScore
    FROM ParsedPostTags PPT
    JOIN PostDetailsWithHistory PDH ON PPT.PostId = PDH.PostId
    GROUP BY PPT.TagName
    HAVING COUNT(DISTINCT PPT.PostId) > 500 AND SUM(PDH.ViewCount) > 1000000
    ORDER BY TotalTaggedPostViews DESC
),
RankedUserPosts AS (
    SELECT
        PDH.PostId,
        PDH.OwnerUserId,
        PDH.PostScore,
        PDH.ViewCount,
        PDH.PostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY PDH.OwnerUserId ORDER BY PDH.PostScore DESC, PDH.ViewCount DESC) AS RankByUserScoreAndViews,
        RANK() OVER (PARTITION BY PDH.OwnerUserId, PDH.PostTypeId ORDER BY PDH.PostCreationDate) AS PostOrderInTypeForUser,
        LAG(PDH.PostScore, 1, 0) OVER (PARTITION BY PDH.OwnerUserId ORDER BY PDH.PostCreationDate) AS PreviousPostScore,
        LEAD(PDH.PostScore, 1, 0) OVER (PARTITION BY PDH.OwnerUserId ORDER BY PDH.PostCreationDate) AS NextPostScore
    FROM PostDetailsWithHistory PDH
    WHERE PDH.PostTypeId = 1 -- Only rank questions for this specific CTE
),
MainQuestionAnalysis AS (
    SELECT
        UA.UserId,
        UA.DisplayName,
        UA.Reputation,
        UA.ReputationTier,
        UA.TotalOwnedPosts,
        UA.TotalCommentsMade,
        UA.TotalBadgesEarned,
        UA.TotalBountyProvided,
        UA.DaysSinceLastAccess,
        PDH.PostId,
        COALESCE(PDH.Title, 'Untitled Post ID: ' || PDH.PostId::TEXT || ' - ' || SUBSTRING(REPLACE(REPLACE(PDH.Body, '<p>', ''), '</p>', ''), 1, 50)) AS DisplayPostTitleSnippet,
        PT.Name AS PostTypeName,
        PDH.PostCreationDate,
        PDH.PostScore,
        PDH.ViewCount,
        PDH.UpVotesReceived,
        PDH.DownVotesReceived,
        PDH.AvgCommentScore,
        PDH.EditCount,
        PDH.CloseHistoryCount,
        PDH.DuplicateLinkCount,
        PDH.LatestCommentSnippet,
        RP.RankByUserScoreAndViews,
        RP.PreviousPostScore,
        RP.NextPostScore,
        -- String expressions and complicated predicates
        POSITION('benchmark' IN LOWER(PDH.Body)) > 0 OR POSITION('optimize' IN LOWER(PDH.Title)) > 0 AS ContainsPerformanceKeywords,
        COALESCE(REPLACE(REPLACE(SUBSTRING(PDH.Body, POSITION('<pre>' IN PDH.Body), 100), '<pre>', ''), '</pre>', ''), '') AS CodeSnippetSample, -- Attempt to extract a code snippet
        -- Correlated subquery for a tag list
        ARRAY_TO_STRING(ARRAY(SELECT TagName FROM ParsedPostTags WHERE PostId = PDH.PostId ORDER BY TagName LIMIT 5), ', ') AS Top5Tags,
        CASE
            WHEN PDH.AcceptedAnswerId IS NOT NULL AND PDH.AnswerCount > 0 AND PDH.ClosedDate IS NULL THEN 'Solved & Open'
            WHEN PDH.AnswerCount > 0 AND PDH.ClosedDate IS NULL THEN 'Answered but Unaccepted'
            WHEN PDH.ClosedDate IS NOT NULL THEN 'Closed Question'
            WHEN PDH.ViewCount > 5000 AND PDH.TotalPostComments > 10 THEN 'High Engagement Unanswered'
            ELSE 'Other Status'
        END AS QuestionDetailedStatus,
        -- Complicated calculation: interaction-to-view ratio, handling division by zero
        CAST( (PDH.UpVotesReceived + PDH.DownVotesReceived + PDH.TotalPostComments + COALESCE(PDH.FavoriteCount, 0)) AS NUMERIC)
            / NULLIF(PDH.ViewCount, 0) AS EngagementRatio,
        EXTRACT(DAY FROM (NOW() - PDH.PostCreationDate)) AS DaysSincePostCreation,
        COALESCE(U_Editor.DisplayName, 'Original Owner/Community') AS LastEditorDisplayName,
        -- Correlated EXISTS subquery for badge check
        (SELECT EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UA.UserId AND B.Class = 1 AND B.TagBased = FALSE)) AS HasGoldNamedBadge,
        HTS.TagName IS NOT NULL AS IsHotTagPost,
        PDH.PostId = PDH.AcceptedAnswerId AS IsSelfAcceptedAnswer,
        'High-Performance Question' AS ResultCategory
    FROM UserAggregates UA
    JOIN PostDetailsWithHistory PDH ON UA.UserId = PDH.OwnerUserId
    JOIN PostTypes PT ON PDH.PostTypeId = PT.Id
    JOIN RankedUserPosts RP ON PDH.PostId = RP.PostId AND PDH.OwnerUserId = RP.OwnerUserId -- Join with ranked posts
    LEFT JOIN Users U_Editor ON PDH.LastEditorUserId = U_Editor.Id
    LEFT JOIN ParsedPostTags PPT ON PDH.PostId = PPT.PostId
    LEFT JOIN HotTagsCategorization HTS ON PPT.TagName = HTS.TagName -- Outer join for hot tag categorization
    WHERE
        UA.ReputationTier IN ('Expert', 'Legendary')
        AND PDH.PostTypeId = 1 -- Focus on questions
        AND PDH.PostScore >= 50
        AND PDH.ViewCount >= 10000
        AND PDH.CreationDate >= (NOW() - INTERVAL '3 year') -- Recent active posts
        AND PDH.AnswerCount >= 2
        AND PDH.EditCount >= 3 -- Posts with significant edits
        AND RP.RankByUserScoreAndViews <= 10 -- Only top 10 questions per user
        AND NOT EXISTS ( -- Correlated subquery: check if post was deleted and then undeleted within a short period
            SELECT 1 FROM PostHistory PH1
            WHERE PH1.PostId = PDH.PostId
              AND PH1.PostHistoryTypeId = 12 -- Post Deleted
              AND EXISTS (
                  SELECT 1 FROM PostHistory PH2
                  WHERE PH2.PostId = PDH.PostId
                    AND PH2.PostHistoryTypeId = 13 -- Post Undeleted
                    AND PH2.CreationDate > PH1.CreationDate
                    AND (PH2.CreationDate - PH1.CreationDate) < INTERVAL '7 day' -- Undeleted within 7 days
              )
        )
    GROUP BY
        UA.UserId, UA.DisplayName, UA.Reputation, UA.ReputationTier, UA.TotalOwnedPosts, UA.TotalCommentsMade, UA.TotalBadgesEarned, UA.TotalBountyProvided, UA.DaysSinceLastAccess,
        PDH.PostId, PDH.PostTypeId, PDH.OwnerUserId, PDH.LastEditorUserId, PDH.PostCreationDate, PDH.LastActivityDate, PDH.PostScore, PDH.ViewCount, PDH.AnswerCount, PDH.TotalPostComments, PDH.FavoriteCount, PDH.Title, PDH.Tags, PDH.Body, PDH.AcceptedAnswerId, PDH.ParentId, PDH.ClosedDate,
        PDH.UpVotesReceived, PDH.DownVotesReceived, PDH.EditCount, PDH.CloseHistoryCount, PDH.LastCloseHistoryDate, PDH.LatestCommentSnippet, PDH.AvgCommentScore, PDH.TotalRelatedLinks, PDH.DuplicateLinkCount,
        PT.Name,
        RP.RankByUserScoreAndViews, RP.PreviousPostScore, RP.NextPostScore,
        U_Editor.DisplayName,
        HTS.TagName
    HAVING COUNT(DISTINCT PPT.TagName) > 1 -- Ensure posts have at least 2 distinct tags
),
ControversialPosts AS (
    SELECT
        UA.UserId,
        UA.DisplayName,
        UA.Reputation,
        UA.ReputationTier,
        UA.TotalOwnedPosts,
        UA.TotalCommentsMade,
        UA.TotalBadgesEarned,
        UA.TotalBountyProvided,
        UA.DaysSinceLastAccess,
        PDH.PostId,
        COALESCE(PDH.Title, 'Untitled Post ID: ' || PDH.PostId::TEXT || ' - ' || SUBSTRING(REPLACE(REPLACE(PDH.Body, '<p>', ''), '</p>', ''), 1, 50)) AS DisplayPostTitleSnippet,
        PT.Name AS PostTypeName,
        PDH.PostCreationDate,
        PDH.PostScore,
        PDH.ViewCount,
        PDH.UpVotesReceived,
        PDH.DownVotesReceived,
        PDH.AvgCommentScore,
        PDH.EditCount,
        PDH.CloseHistoryCount,
        PDH.DuplicateLinkCount,
        PDH.LatestCommentSnippet,
        NULL::BIGINT AS RankByUserScoreAndViews, -- Not applicable for this category, ensuring type compatibility
        NULL::INT AS PreviousPostScore,
        NULL::INT AS NextPostScore,
        POSITION('controversy' IN LOWER(PDH.Body)) > 0 OR POSITION('disagree' IN LOWER(PDH.Title)) > 0 AS ContainsPerformanceKeywords, -- Reusing column, semantic shift
        COALESCE(REPLACE(REPLACE(SUBSTRING(PDH.Body, POSITION('<pre>' IN PDH.Body), 100), '<pre>', ''), '</pre>', ''), '') AS CodeSnippetSample,
        ARRAY_TO_STRING(ARRAY(SELECT TagName FROM ParsedPostTags WHERE PostId = PDH.PostId ORDER BY TagName LIMIT 5), ', ') AS Top5Tags,
        'Highly Controversial' AS QuestionDetailedStatus, -- Simplified status
        CAST( (PDH.UpVotesReceived + PDH.DownVotesReceived + PDH.TotalPostComments + COALESCE(PDH.FavoriteCount, 0)) AS NUMERIC)
            / NULLIF(PDH.ViewCount, 0) AS EngagementRatio,
        EXTRACT(DAY FROM (NOW() - PDH.PostCreationDate)) AS DaysSincePostCreation,
        COALESCE(U_Editor.DisplayName, 'Original Owner/Community') AS LastEditorDisplayName,
        (SELECT EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UA.UserId AND B.Class = 2 AND B.TagBased = FALSE)) AS HasGoldNamedBadge, -- Checking for Silver named badge for controversy
        HTS.TagName IS NOT NULL AS IsHotTagPost,
        PDH.PostId = PDH.AcceptedAnswerId AS