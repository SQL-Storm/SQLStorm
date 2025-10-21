-- {"query": "49047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2247} 

WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(P.Score) AS TotalPostScore,
        SUM(P.ViewCount) AS TotalPostViewCount,
        SUM(P.FavoriteCount) AS TotalFavoriteCount,
        SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        -- Count answers provided by this user that were accepted by any question
        SUM(CASE WHEN P.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.PostTypeId = 1 AND Q.AcceptedAnswerId = P.Id) THEN 1 ELSE 0 END) AS AcceptedAnswersProvided,
        MAX(P.CreationDate) AS LatestPostDate
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.CreationDate >= '2020-01-01 00:00:00' -- Focus on recent activity
      AND P.PostTypeId IN (1, 2) -- Only questions and answers
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
UserCommentActivity AS (
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        MAX(C.CreationDate) AS LatestCommentDate
    FROM Comments C
    WHERE C.CreationDate >= '2020-01-01 00:00:00'
      AND C.UserId IS NOT NULL
    GROUP BY C.UserId
),
UserBadgeAwards AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
UserPostHistoryContribution AS (
    SELECT
        PH.UserId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount, -- Edits (Title, Body, Tags)
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseEventsOnOwnPosts, -- Post closed event for a post owned by this user
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (8, 9) THEN 1 END) AS RollbacksOnOwnPosts, -- Rollbacks (Body, Tags) on posts
        COUNT(DISTINCT PH.PostId) AS DistinctPostsWithHistoryEvents
    FROM PostHistory PH
    WHERE PH.CreationDate >= '2020-01-01 00:00:00'
      AND PH.UserId IS NOT NULL -- User initiated history events
    GROUP BY PH.UserId
),
UserTagContributions AS (
    SELECT
        U.Id AS UserId,
        T.TagName,
        COUNT(P.Id) AS PostsInTag,
        SUM(P.Score) AS ScoreInTag
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    JOIN Tags T ON P.Tags LIKE '%<' || T.TagName || '>%' -- Simplified tag matching, potentially slow
    WHERE P.CreationDate >= '2020-01-01 00:00:00'
      AND P.PostTypeId IN (1, 2)
      AND (T.TagName = 'sql' OR T.TagName = 'database' OR T.TagName = 'postgresql' OR T.TagName = 'mysql' OR T.TagName = 'performance')
    GROUP BY U.Id, T.TagName
),
UserAggregatedTagScores AS (
    SELECT
        UserId,
        SUM(PostsInTag) AS TotalPostsInRelevantTags,
        SUM(ScoreInTag) AS TotalScoreInRelevantTags
    FROM UserTagContributions
    GROUP BY UserId
),
FinalUserStats AS (
    SELECT
        UCS.UserId,
        UCS.Reputation,
        UCS.UserCreationDate,
        UCS.UserLastAccessDate,
        UCS.TotalPosts,
        UCS.QuestionsAsked,
        UCS.AnswersProvided,
        UCS.TotalPostScore,
        UCS.TotalPostViewCount,
        UCS.TotalFavoriteCount,
        UCS.QuestionsWithAcceptedAnswers,
        UCS.AcceptedAnswersProvided,
        COALESCE(UCA.TotalComments, 0) AS TotalComments,
        COALESCE(UCA.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(UBA.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBA.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBA.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(UPHC.EditCount, 0) AS EditCount,
        COALESCE(UPHC.CloseEventsOnOwnPosts, 0) AS CloseEventsOnOwnPosts,
        COALESCE(UPHC.RollbacksOnOwnPosts, 0) AS RollbacksOnOwnPosts,
        COALESCE(UATS.TotalPostsInRelevantTags, 0) AS TotalPostsInRelevantTags,
        COALESCE(UATS.TotalScoreInRelevantTags, 0) AS TotalScoreInRelevantTags,
        GREATEST(UCS.LatestPostDate, COALESCE(UCA.LatestCommentDate, '1900-01-01 00:00:00'), COALESCE(UBA.LatestBadgeDate, '1900-01-01 00:00:00')) AS LastActivityDate
    FROM UserContributionSummary UCS
    LEFT JOIN UserCommentActivity UCA ON UCS.UserId = UCA.UserId
    LEFT JOIN UserBadgeAwards UBA ON UCS.UserId = UBA.UserId
    LEFT JOIN UserPostHistoryContribution UPHC ON UCS.UserId = UPHC.UserId
    LEFT JOIN UserAggregatedTagScores UATS ON UCS.UserId = UATS.UserId
    WHERE UCS.Reputation > 1000 -- Filter for more established users
      AND UCS.TotalPosts >= 10 -- Minimum activity threshold
)
SELECT
    FUS.UserId,
    U.DisplayName,
    FUS.Reputation,
    FUS.TotalPosts,
    FUS.QuestionsAsked,
    FUS.AnswersProvided,
    FUS.TotalPostScore,
    FUS.TotalPostViewCount,
    FUS.TotalFavoriteCount,
    FUS.QuestionsWithAcceptedAnswers,
    FUS.AcceptedAnswersProvided,
    FUS.TotalComments,
    FUS.TotalCommentScore,
    FUS.GoldBadges,
    FUS.SilverBadges,
    FUS.BronzeBadges,
    FUS.EditCount,
    FUS.TotalPostsInRelevantTags,
    FUS.TotalScoreInRelevantTags,
    FUS.LastActivityDate,
    -- Elaborate custom score for ranking user influence and activity
    (
        FUS.Reputation * 0.05 -- Base reputation contribution
        + FUS.TotalPostScore * 0.4 -- Score from all posts
        + (FUS.AcceptedAnswersProvided * 15) -- High value for accepted answers
        + (FUS.QuestionsWithAcceptedAnswers * 5) -- Value for questions that got accepted answers
        + (FUS.GoldBadges * 100 + FUS.SilverBadges * 20 + FUS.BronzeBadges * 5) -- Badge value
        + (FUS.TotalScoreInRelevantTags * 0.8) -- Emphasize score in specific tags
        + (FUS.TotalComments * 0.1 + FUS.TotalCommentScore * 0.2) -- Comment engagement
        + (FUS.TotalPostViewCount / 1000.0) -- View count as popularity metric
        + (FUS.TotalFavoriteCount * 2) -- Favorite count as engagement metric
        - (FUS.CloseEventsOnOwnPosts * 50) -- Penalty for posts that get closed
        - (FUS.RollbacksOnOwnPosts * 25) -- Penalty for rollbacks indicating lower quality edits
        + (FUS.EditCount * 0.5) -- Small positive for editing, indicating maintenance
        - (EXTRACT(EPOCH FROM (NOW() - FUS.LastActivityDate)) / (3600 * 24 * 30)) * 10 -- Recent activity bonus (penalty for inactivity, scaled by months)
    ) AS InfluenceScore
FROM FinalUserStats FUS
JOIN Users U ON FUS.UserId = U.Id
WHERE U.DisplayName IS NOT NULL -- Exclude users without display names
  AND U.DisplayName != 'Community' -- Exclude community user
ORDER BY InfluenceScore DESC, FUS.Reputation DESC, U.CreationDate ASC
LIMIT 100;
