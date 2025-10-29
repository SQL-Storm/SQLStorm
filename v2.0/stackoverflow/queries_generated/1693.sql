-- {"query": "1693.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2772} 

WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT B.Id) AS TotalBadgesAwarded,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(P.Score) AS TotalPostScoreReceived,
        AVG(P.Score) AS AveragePostScoreReceived,
        COUNT(DISTINCT CASE WHEN V.VoteTypeId IN (2, 3) THEN V.PostId ELSE NULL END) AS PostsVotedOn,
        MAX(P.LastActivityDate) AS LatestPostActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId -- Votes made by this user
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 0 OR COUNT(DISTINCT C.Id) > 0
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.Title,
        P.Body,
        P.Tags,
        LENGTH(P.Body) AS BodyLength,
        COALESCE(ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'), 1), 0) AS TagCount,
        EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate)) / (60 * 60 * 24.0) AS DaysSinceLastActivity, -- Convert to days
        (
            SELECT AVG(P_sub.Score)
            FROM Posts P_sub
            WHERE P_sub.OwnerUserId = P.OwnerUserId
              AND P_sub.Id != P.Id
              AND P_sub.PostTypeId = P.PostTypeId
              AND P_sub.CreationDate BETWEEN P.CreationDate - INTERVAL '1 year' AND P.CreationDate + INTERVAL '1 year'
        ) AS AvgCorrelatedSiblingPostScoreByOwner, -- Correlated Subquery
        SUM(P.ViewCount) OVER (PARTITION BY P.OwnerUserId) AS TotalViewsOfAllPostsByOwner,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC, P.CreationDate DESC) AS RankInPostTypeByScoreViews,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS UserPostScoreRank,
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScoreByOwner,
        CASE
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 'Accepted_Answered_Question'
            WHEN P.PostTypeId = 1 AND P.AnswerCount > 0 THEN 'Answered_Question_No_Accepted'
            WHEN P.PostTypeId = 1 THEN 'Unanswered_Question'
            WHEN P.PostTypeId = 2 AND P.ParentId IS NOT NULL THEN 'Answer_To_Question'
            WHEN P.PostTypeId = 4 THEN 'Tag_Wiki_Excerpt'
            WHEN P.PostTypeId = 5 THEN 'Tag_Wiki'
            ELSE 'Other_PostType'
        END AS DetailedPostCategory,
        COALESCE(P.FavoriteCount, 0) AS ValidFavoriteCount, -- NULL logic example
        COALESCE(P.ClosedDate, P.CommunityOwnedDate) IS NOT NULL AS IsClosedOrCommunityOwned, -- NULL logic check
        P.Title IS NULL OR P.Title = '' OR TRIM(P.Title) = '' AS IsTitleMissing
    FROM Posts P
    INNER JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community user posts etc.
      AND P.CreationDate >= (NOW() - INTERVAL '5 year') -- Filter for relatively recent posts
      AND P.Body IS NOT NULL AND LENGTH(P.Body) > 50 -- Ensure meaningful content
),
PostHistoryTimeline AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12) THEN 1 ELSE 0 END) AS CloseDeleteEvents, -- Post Closed or Deleted
        MAX(PH.CreationDate) AS LatestHistoryEventDate,
        MIN(PH.CreationDate) AS EarliestHistoryEventDate,
        COUNT(DISTINCT PH.UserId) AS UniqueHistoryContributors,
        -- Calculate time difference between the first and last history event for a post
        EXTRACT(EPOCH FROM (MAX(PH.CreationDate) - MIN(PH.CreationDate))) / (60 * 60 * 24.0) AS DaysActiveInHistory
    FROM PostHistory PH
    GROUP BY PH.PostId
),
PostLinkAggregation AS (
    SELECT
        P.Id AS PostId,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        COUNT(DISTINCT PL.RelatedPostId) AS UniqueRelatedPosts
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    GROUP BY P.Id
),
TagPerformance AS (
    SELECT
        T.TagName,
        AVG(P.Score) AS AvgScoreForTag,
        COUNT(P.Id) AS TotalPostsWithTag,
        SUM(P.ViewCount) AS TotalViewsForTag
    FROM Tags T
    INNER JOIN Posts P ON P.Tags ILIKE '%<' || T.TagName || '>%' -- More robust tag matching
    GROUP BY T.TagName
    HAVING COUNT(P.Id) > 100 -- Only consider sufficiently used tags
)
-- Main Query: Combine and analyze everything
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.GoldBadgesCount,
    UES.TotalQuestionsOwned,
    UES.TotalAnswersOwned,
    UES.TotalCommentsMade,
    UES.LatestPostActivityDate AS UserLatestActivity,
    PCA.PostId,
    PCA.PostTypeName,
    PCA.Title,
    PCA.Score AS PostCurrentScore,
    PCA.ViewCount AS PostCurrentViewCount,
    PCA.PostCommentCount,
    PCA.ValidFavoriteCount,
    PCA.BodyLength,
    PCA.TagCount,
    PCA.DaysSinceLastActivity,
    PCA.AvgCorrelatedSiblingPostScoreByOwner,
    PCA.RankInPostTypeByScoreViews,
    PCA.UserPostScoreRank,
    PCA.DetailedPostCategory,
    PCA.PreviousPostScoreByOwner,
    PIH.EditCount AS PostEditCount,
    PIH.CloseDeleteEvents,
    PIH.DaysActiveInHistory,
    PLA.LinkedPostsCount,
    PLA.DuplicatePostsCount,
    TP.AvgScoreForTag,
    TP.TotalPostsWithTag,
    -- Complex calculated metric: User Influence Score (weighted by post engagement, user's overall contribution, and badge status)
    ROUND(
        (UES.Reputation * 0.1) -- Base reputation
        + (UES.TotalQuestionsOwned * 0.5 + UES.TotalAnswersOwned * 0.3) -- Content contribution
        + (UES.GoldBadgesCount * 10) -- Gold badge bonus
        + (COALESCE(UES.AveragePostScoreReceived, 0) * 2) -- Average post quality
        + (CASE WHEN PCA.IsClosedOrCommunityOwned THEN -5 ELSE 0 END) -- Penalty for closed/community owned posts
        + (CASE WHEN PCA.DaysSinceLastActivity < 30 THEN 10 ELSE 0 END) -- Bonus for very recent activity
        - (CASE WHEN PCA.IsTitleMissing THEN 2 ELSE 0 END) -- Penalty for missing title
    , 2) AS UserInfluenceScore,
    -- Post Quality-to-Activity Ratio: How well a post performs given its activity and linked status
    ROUND(
        (CAST(PCA.Score AS NUMERIC) / NULLIF(PCA.ViewCount, 0.001)) * 100 -- Score per view percentage
        + (PCA.ValidFavoriteCount * 0.5) -- Favorites contribute
        + (PCA.PostCommentCount * 0.2) -- Comments contribute
        + (CASE WHEN PCA.TagCount > 5 THEN 1 ELSE 0 END) -- Bonus for well-tagged posts
        - (CAST(PIH.CloseDeleteEvents AS NUMERIC) * 3) -- Penalty for close/delete events
        + (CAST(PLA.DuplicatePostsCount AS NUMERIC) * -1) -- Penalty for being a duplicate
        + (CAST(PLA.LinkedPostsCount AS NUMERIC) * 0.5) -- Bonus for being linked
    , 3) AS PostQualityActivityRatio,
    -- String Expression: Analyze post body for keywords and length
    CASE
        WHEN PCA.Body ILIKE '%performance%' AND PCA.Body ILIKE '%optimization%' THEN 'High_Performance_Topic'
        WHEN PCA.Body ILIKE '%error%' OR PCA.Body ILIKE '%bug%' THEN 'Troubleshooting_Topic'
        WHEN PCA.BodyLength > 1500 AND PCA.TagCount > 3 THEN 'Elaborate_Technical_Content'
        WHEN PCA.BodyLength < 200 THEN 'Concise_Content'
        ELSE 'General_Content'
    END AS ContentTopicAndStyle
FROM UserEngagementSummary UES
INNER JOIN PostContentAnalysis PCA ON UES.UserId = PCA.OwnerUserId
LEFT JOIN PostHistoryTimeline PIH ON PCA.PostId = PIH.PostId
LEFT JOIN PostLinkAggregation PLA ON PCA.PostId = PLA.PostId
LEFT JOIN TagPerformance TP ON PCA.Tags ILIKE '%<' || TP.TagName || '>%' -- Join with TagPerformance for common tags
WHERE UES.GoldBadgesCount >= 1 -- Only analyze users with at least one gold badge
  AND PCA.Score >= 5 -- Focus on reasonably performing posts
  AND PCA.ViewCount >= 50 -- Ensure posts have some visibility
  AND PCA.DaysSinceLastActivity < 180 -- Posts active within the last 6 months
  AND PCA.RankInPostTypeByScoreViews <= 50 -- Top 50 posts by score/views within their type
  AND (PCA.PostTypeName = 'Question' OR PCA.PostTypeName = 'Answer') -- Focus on core post types
ORDER BY
    UserInfluenceScore DESC,
    PostQualityActivityRatio DESC,
    UES.Reputation DESC,
    PCA.PostCreationDate DESC
LIMIT 5000;
