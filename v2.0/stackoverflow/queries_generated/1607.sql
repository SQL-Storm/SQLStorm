-- {"query": "1607.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3449} 

WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User #' || U.Id) AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesCast, -- Upvotes *cast by* the user
        U.DownVotes AS UserDownVotesCast, -- Downvotes *cast by* the user
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V_received.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceivedOnPosts,
        SUM(CASE WHEN V_received.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceivedOnPosts,
        COALESCE(AVG(NULLIF(P.Score, 0)), 0.0) AS AvgPostScoreOwned,
        SUM(P.Score) AS TotalPostScoreOwned,
        -- Correlated subquery to calculate the ratio of accepted answers among all answers owned by the user
        COALESCE(
            CAST(
                (SELECT COUNT(DISTINCT P_ans.Id)
                 FROM Posts P_ans
                 WHERE P_ans.OwnerUserId = U.Id
                   AND P_ans.PostTypeId = 2
                   AND EXISTS (SELECT 1 FROM Posts PQ_parent WHERE PQ_parent.Id = P_ans.ParentId AND PQ_parent.AcceptedAnswerId = P_ans.Id))
            AS DECIMAL) / NULLIF(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0),
        0.0) AS AcceptedAnswerRatio,
        RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V_received ON P.Id = V_received.PostId -- Votes received on *any* post owned by the user
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostDetailedHistory AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.Title,
        P.Tags,
        P.Score AS PostScore,
        P.OwnerUserId,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        -- Window function to calculate average time in hours between consecutive edits for a post, handling NULLs
        COALESCE(AVG(
            EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate))) / 3600.0
        ) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6) AND PH.CreationDate > LAG(PH.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.Id ORDER BY PH.CreationDate)), 0.0) AS AvgEditIntervalHours,
        -- Correlated subquery to find the owner's reputation at the time of post creation
        (SELECT U_owner.Reputation FROM Users U_owner WHERE U_owner.Id = P.OwnerUserId AND U_owner.CreationDate <= P.CreationDate ORDER BY U_owner.CreationDate DESC LIMIT 1) AS OwnerReputationAtCreation,
        -- Determine the primary close reason if closed, using MAX to pick one if multiple close events exist
        MAX(CASE WHEN PH_close.PostHistoryTypeId = 10 THEN CRT.Name ELSE NULL END) AS PrimaryCloseReason,
        COUNT(DISTINCT PL_linked.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT PL_duplicate.RelatedPostId) AS DuplicatePostsCount,
        COALESCE(P.ContentLicense, 'Unknown License') AS ContentLicenseType,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN P.PostTypeId = 1 AND P.AnswerCount = 0 AND P.ClosedDate IS NULL THEN 'Unanswered'
            ELSE 'Open'
        END AS PostStatusCategory,
        EXTRACT(EPOCH FROM (P.ClosedDate - P.CreationDate)) / 86400.0 AS DaysToClose -- in days, NULL if not closed
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN PostHistory PH_close ON P.Id = PH_close.PostId AND PH_close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CRT ON PH_close.Comment IS NOT NULL AND CAST(PH_close.Comment AS SMALLINT) = CRT.Id
    LEFT JOIN PostLinks PL_linked ON P.Id = PL_linked.PostId AND PL_linked.LinkTypeId = 1
    LEFT JOIN PostLinks PL_duplicate ON P.Id = PL_duplicate.PostId AND PL_duplicate.LinkTypeId = 3
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.LastActivityDate, P.ClosedDate, P.Title, P.Tags, P.Score,
             P.OwnerUserId, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ContentLicense, P.CommunityOwnedDate, P.AcceptedAnswerId
),
TagPerformanceMetrics AS (
    SELECT
        Tag.TagName,
        COUNT(DISTINCT P.Id) AS PostsWithTagCount,
        SUM(P.ViewCount) AS TotalViewsForTag,
        SUM(P.Score) AS TotalScoreForTag,
        COALESCE(AVG(NULLIF(P.AnswerCount, 0)), 0.0) AS AvgAnswerCountForTag,
        MAX(P.CreationDate) AS LatestPostDateForTag,
        MIN(P.CreationDate) AS EarliestPostDateForTag,
        COUNT(DISTINCT P.OwnerUserId) AS UniqueQuestionersForTag,
        RANK() OVER (ORDER BY SUM(P.Score) DESC, COUNT(DISTINCT P.Id) DESC) AS TagScoreRank
    FROM Posts P
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS Tag(TagName)
    WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1
    GROUP BY Tag.TagName
),
-- Set operator example: Combine top N users by reputation and top N users by total post score
TopUsersCombined AS (
    (SELECT UserId, UserDisplayName, Reputation, TotalPostScoreOwned, 'HighReputation' AS UserCategory FROM UserEngagementSummary ORDER BY Reputation DESC LIMIT 100)
    UNION ALL
    (SELECT UserId, UserDisplayName, Reputation, TotalPostScoreOwned, 'HighPostScore' AS UserCategory FROM UserEngagementSummary ORDER BY TotalPostScoreOwned DESC LIMIT 100)
)
SELECT
    UES.UserId,
    UES.UserDisplayName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.LastAccessDate,
    UES.UserProfileViews,
    UES.TotalPostsOwned,
    UES.QuestionCount,
    UES.AnswerCount,
    UES.TotalCommentsMade,
    UES.TotalUpVotesReceivedOnPosts,
    UES.TotalDownVotesReceivedOnPosts,
    UES.TotalPostScoreOwned,
    UES.AcceptedAnswerRatio,
    PDH.PostId,
    PDH.PostTypeId,
    PDH.PostCreationDate,
    PDH.PostScore,
    PDH.ViewCount,
    PDH.EditCount,
    PDH.AvgEditIntervalHours,
    PDH.PrimaryCloseReason,
    PDH.LinkedPostsCount,
    PDH.DuplicatePostsCount,
    PDH.PostStatusCategory,
    PDH.DaysToClose,
    TPM.TagName AS TopContributingTag,
    TPM.TotalScoreForTag AS TopTagScore,
    -- Complicated calculation for a "Weighted User Impact Score"
    (UES.Reputation * 0.1
     + UES.TotalPostScoreOwned * 0.5
     + UES.TotalUpVotesReceivedOnPosts * 0.2
     + UES.AcceptedAnswerRatio * 1000.0 -- Scale accepted answer ratio
     - UES.TotalDownVotesReceivedOnPosts * 0.1
     + (UES.QuestionCount + UES.AnswerCount + UES.TotalCommentsMade) * 0.05
    ) AS WeightedUserImpactScore,
    -- String manipulation and conditional logic on post title
    UPPER(SUBSTRING(PDH.Title FROM 1 FOR 1)) || LOWER(SUBSTRING(PDH.Title FROM 2)) AS FormattedPostTitle,
    -- Determine if post title contains common keywords using ILIKE (case-insensitive)
    CASE
        WHEN PDH.Title ILIKE '%error%' OR PDH.Title ILIKE '%problem%' THEN 'Problem-solving'
        WHEN PDH.Title ILIKE '%how to%' OR PDH.Title ILIKE '%guide%' THEN 'Instructional'
        WHEN PDH.Title IS NULL THEN 'No Title'
        ELSE 'General'
    END AS TitleKeywordCategory,
    -- Calculate the current age of the post in days, handling potential future dates
    GREATEST(0.0, EXTRACT(EPOCH FROM (NOW() - PDH.PostCreationDate)) / 86400.0) AS PostAgeDays,
    -- Window function: Rank posts by their view count within a specific post type
    ROW_NUMBER() OVER (PARTITION BY PDH.PostTypeId ORDER BY PDH.ViewCount DESC, PDH.PostCreationDate DESC) AS PostViewRankOfType,
    -- Null logic demonstration
    COALESCE(UES.AcceptedAnswerRatio, 0.0) AS ActualAcceptedAnswerRatio,
    NULLIF(UES.TotalPostsOwned, 0) AS NonZeroPostsOwnedCount,
    -- Correlated subquery to check if a user has any badges of class 1 (Gold)
    EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UES.UserId AND B.Class = 1) AS HasGoldBadge,
    -- Correlated subquery to sum total bounty on a post
    COALESCE((SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = PDH.PostId AND V.VoteTypeId = 8), 0) AS TotalBountyOnPost
FROM UserEngagementSummary UES
LEFT JOIN PostDetailedHistory PDH ON UES.UserId = PDH.OwnerUserId
LEFT JOIN TagPerformanceMetrics TPM ON
    PDH.PostTypeId = 1 AND PDH.Tags IS NOT NULL AND
    -- Correlated subquery to find the tag with the highest total score among the post's tags
    TPM.TagName = (
        SELECT Tag_Inner.TagName
        FROM Posts P_Inner
        CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P_Inner.Tags FROM 2 FOR LENGTH(P_Inner.Tags) - 2), '><')) AS Tag_Inner(TagName)
        JOIN TagPerformanceMetrics TPM_Inner ON Tag_Inner.TagName = TPM_Inner.TagName
        WHERE P_Inner.Id = PDH.PostId AND P_Inner.PostTypeId = 1
        ORDER BY TPM_Inner.TotalScoreForTag DESC, TPM_Inner.PostsWithTagCount DESC
        LIMIT 1
    )
WHERE
    UES.Reputation > 500
    AND PDH.PostScore >= 0
    AND PDH.LastActivityDate >= '2022-01-01'
    AND (PDH.PostTypeId = 1 OR (PDH.PostTypeId = 2 AND PDH.AnswerCount > 0))
    AND LENGTH(PDH.Title) BETWEEN 10 AND 150
    -- Nested subquery with aggregation in WHERE clause
    AND UES.TotalPostsOwned > (SELECT AVG(TotalPostsOwned) FROM UserEngagementSummary WHERE ReputationRank <= 100 AND TotalPostsOwned IS NOT NULL)
    -- Exclude users from specific top categories if their post score is below a threshold
    AND UES.UserId NOT IN (SELECT UserId FROM TopUsersCombined WHERE UserCategory = 'HighReputation' AND TotalPostScoreOwned < 1000)
GROUP BY
    UES.UserId, UES.UserDisplayName, UES.Reputation, UES.UserCreationDate, UES.LastAccessDate, UES.UserProfileViews,
    UES.TotalPostsOwned, UES.QuestionCount, UES.AnswerCount, UES.TotalCommentsMade,
    UES.TotalUpVotesReceivedOnPosts, UES.TotalDownVotesReceivedOnPosts, UES.TotalPostScoreOwned, UES.AcceptedAnswerRatio,
    PDH.PostId, PDH.PostTypeId, PDH.PostCreationDate, PDH.PostScore, PDH.ViewCount, PDH.EditCount,
    PDH.AvgEditIntervalHours, PDH.PrimaryCloseReason, PDH.LinkedPostsCount, PDH.DuplicatePostsCount,
    PDH.PostStatusCategory, PDH.DaysToClose, PDH.Title, PDH.LastActivityDate, TPM.TagName, TPM.TotalScoreForTag
HAVING
    (UES.Reputation * 0.1 + UES.TotalPostScoreOwned * 0.5 + UES.TotalUpVotesReceivedOnPosts * 0.2 + UES.AcceptedAnswerRatio * 1000.0 - UES.TotalDownVotesReceivedOnPosts * 0.1 + (UES.QuestionCount + UES.AnswerCount + UES.TotalCommentsMade) * 0.05) > 1000
    AND COUNT(DISTINCT PDH.PostId) > 1
    AND MAX(GREATEST(0.0, EXTRACT(EPOCH FROM (NOW() - PDH.PostCreationDate)) / 86400.0)) < 1000
ORDER BY
    WeightedUserImpactScore DESC,
    UES.LastAccessDate DESC,
    PostViewRankOfType ASC
LIMIT 1000;
