-- {"query": "1179.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2764} 

WITH UserPostAggregates AS (
    -- Aggregates related to posts owned by users
    SELECT
        U.Id AS UserId,
        COUNT(P.Id) AS TotalPostsOwned,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        SUM(P.Score) AS TotalScoreFromPosts,
        MAX(P.Score) AS MaxPostScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AverageAnswerScore,
        COUNT(DISTINCT P.ParentId) AS DistinctQuestionsAnswered,
        SUM(P.ViewCount) AS TotalPostViews,
        MAX(P.CreationDate) AS LatestPostDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id
),
UserCommentVoteAggregates AS (
    -- Aggregates related to comments and votes, both given and received
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT C_Made.Id) AS CommentsMade,
        COUNT(DISTINCT V_Given.Id) AS VotesGiven,
        SUM(CASE WHEN V_Given.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN V_Given.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        COUNT(DISTINCT C_Received.Id) AS CommentsReceivedOnPosts,
        COUNT(DISTINCT V_Received.Id) AS VotesReceivedOnPosts,
        SUM(CASE WHEN V_Received.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceivedOnPosts,
        SUM(CASE WHEN V_Received.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceivedOnPosts
    FROM Users U
    LEFT JOIN Comments C_Made ON U.Id = C_Made.UserId
    LEFT JOIN Votes V_Given ON U.Id = V_Given.UserId
    LEFT JOIN Posts P_Owned ON U.Id = P_Owned.OwnerUserId
    LEFT JOIN Comments C_Received ON P_Owned.Id = C_Received.PostId
    LEFT JOIN Votes V_Received ON P_Owned.Id = V_Received.PostId
    GROUP BY U.Id
),
UserPostHistoryVolatility AS (
    -- Aggregates related to post history, indicating volatility or moderation actions on user's posts
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(PH.Id) AS TotalHistoryEventsOnPosts,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) AND PH.UserId IS DISTINCT FROM P.OwnerUserId THEN PH.Id END) AS EditsByOthersOnPosts, -- Edits not by owner
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS TotalPostsClosed,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS TotalPostsReopened,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.PostId END) AS DistinctPostsClosed
    FROM PostHistory PH
    INNER JOIN Posts P ON PH.PostId = P.Id
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserBadgeSummary AS (
    -- Aggregates related to badges received by users
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        MIN(B.Date) AS FirstBadgeDate,
        MAX(B.Date) AS LastBadgeDate,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgesCount,
        COUNT(CASE WHEN B.TagBased = TRUE THEN B.Id END) AS TagBasedBadgesCount
    FROM Badges B
    GROUP BY B.UserId
),
TagPerformanceMetrics AS (
    -- Calculate average scores and view counts for questions associated with tags
    SELECT
        T.TagName,
        AVG(P.Score) AS AverageQuestionScoreForTag,
        SUM(P.ViewCount) AS TotalQuestionViewsForTag,
        COUNT(P.Id) AS TotalQuestionsWithTag,
        DENSE_RANK() OVER (ORDER BY COUNT(P.Id) DESC, SUM(P.ViewCount) DESC) AS TagPopularityRank
    FROM Posts P
    INNER JOIN Tags T ON T.TagName IN (
        SELECT UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))
    )
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.Tags != ''
    GROUP BY T.TagName
    HAVING COUNT(P.Id) >= 50 -- Only consider tags with at least 50 questions
)
SELECT
    U.Id AS UserID,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    COALESCE(U.Location, 'Not Specified') AS UserLocation,
    U.Views AS ProfileViews,
    COALESCE(UPA.TotalPostsOwned, 0) AS TotalPostsOwned,
    COALESCE(UPA.TotalQuestionsOwned, 0) AS TotalQuestionsOwned,
    COALESCE(UPA.TotalAnswersOwned, 0) AS TotalAnswersOwned,
    COALESCE(UPA.TotalScoreFromPosts, 0) AS TotalContentScore,
    UPA.MaxPostScore,
    COALESCE(UCA.CommentsMade, 0) AS CommentsMade,
    COALESCE(UCA.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(UCA.DownVotesGiven, 0) AS DownVotesGiven,
    COALESCE(UCA.CommentsReceivedOnPosts, 0) AS CommentsReceivedOnPosts,
    COALESCE(UCA.UpVotesReceivedOnPosts, 0) AS UpVotesReceivedOnPosts,
    COALESCE(UCA.DownVotesReceivedOnPosts, 0) AS DownVotesReceivedOnPosts,
    COALESCE(UPHV.EditsByOthersOnPosts, 0) AS EditsByOthersOnPosts,
    COALESCE(UPHV.TotalPostsClosed, 0) AS TotalPostsClosed,
    COALESCE(UPHV.TotalPostsReopened, 0) AS TotalPostsReopened,
    TPM.TagName AS TopContributingTag,
    TPM.AverageQuestionScoreForTag AS TopTagAvgScore,
    TPM.TagPopularityRank AS TopTagRank,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    UBS.FirstBadgeDate,
    UBS.LastBadgeDate,
    COALESCE(UBS.GoldBadgesCount, 0) AS GoldBadgesCount,
    COALESCE(UBS.TagBasedBadgesCount, 0) AS TagBasedBadgesCount,
    -- Complicated Calculations and Expressions
    CASE
        WHEN U.Reputation >= 10000 AND U.LastAccessDate > NOW() - INTERVAL '3 months' THEN 'Veteran_Active'
        WHEN U.Reputation >= 5000 AND COALESCE(UPA.TotalPostsOwned, 0) >= 100 THEN 'Experienced_Contributor'
        WHEN U.CreationDate > NOW() - INTERVAL '1 year' AND U.Reputation < 500 THEN 'Newbie_Explorer'
        WHEN U.Reputation IS NULL OR U.Reputation = 0 THEN 'Unregistered_Phantom' -- NULL logic
        ELSE 'Regular_User'
    END AS UserPersona,
    (COALESCE(U.UpVotes, 0) + COALESCE(U.DownVotes, 0)) AS TotalProfileVotes,
    (COALESCE(U.UpVotes, 0) - COALESCE(U.DownVotes, 0)) AS NetProfileVotes,
    CAST(U.Reputation AS DECIMAL) / (NULLIF(COALESCE(UPA.TotalPostsOwned, 0) + COALESCE(UCA.VotesReceivedOnPosts, 0), 0) + 1) AS ReputationEfficiencyRatio,
    CAST(COALESCE(UPHV.EditsByOthersOnPosts, 0) AS DECIMAL) / (NULLIF(COALESCE(UPA.TotalPostsOwned, 0), 0) + 1) AS PostEditRate,
    COALESCE(UPHV.TotalPostsClosed, 0) - COALESCE(UPHV.TotalPostsReopened, 0) AS NetPostsClosed,
    UPPER(SUBSTRING(COALESCE(U.DisplayName, 'UNKNOWN'), 1, 1)) AS FirstLetterOfDisplayName,
    -- Correlated Subquery: Find the title of the highest scored question for the user
    (
        SELECT P_MaxTitle.Title
        FROM Posts P_MaxTitle
        WHERE P_MaxTitle.OwnerUserId = U.Id
          AND P_MaxTitle.PostTypeId = 1
          AND P_MaxTitle.Title IS NOT NULL
        ORDER BY P_MaxTitle.Score DESC, P_MaxTitle.CreationDate DESC
        LIMIT 1
    ) AS HighestScoredQuestionTitle,
    -- Correlated Subquery: Count distinct editors on the user's latest post
    (
        SELECT COUNT(DISTINCT PH2.UserId)
        FROM PostHistory PH2
        WHERE PH2.PostId = (
            SELECT P_latest.Id
            FROM Posts P_latest
            WHERE P_latest.OwnerUserId = U.Id
            ORDER BY P_latest.CreationDate DESC
            LIMIT 1
        )
    ) AS DistinctEditorsOnLatestPost,
    -- Window Functions
    NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile,
    RANK() OVER (PARTITION BY COALESCE(U.Location, 'Not Specified') ORDER BY U.Reputation DESC) AS RankInLocation,
    AVG(U.Reputation) OVER (PARTITION BY UPPER(SUBSTRING(COALESCE(U.DisplayName, 'UNKNOWN'), 1, 1))) AS AvgReputationByFirstLetter
FROM Users U
LEFT JOIN UserPostAggregates UPA ON U.Id = UPA.UserId
LEFT JOIN UserCommentVoteAggregates UCA ON U.Id = UCA.UserId
LEFT JOIN UserPostHistoryVolatility UPHV ON U.Id = UPHV.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN LATERAL ( -- LATERAL JOIN to get the top tag for each user based on their questions' performance
    SELECT TPM_Inner.TagName, TPM_Inner.AverageQuestionScoreForTag, TPM_Inner.TagPopularityRank
    FROM Posts P_UserTags
    INNER JOIN Tags T ON T.TagName IN (SELECT UNNEST(string_to_array(SUBSTRING(P_UserTags.Tags, 2, LENGTH(P_UserTags.Tags) - 2), '><')))
    INNER JOIN TagPerformanceMetrics TPM_Inner ON T.TagName = TPM_Inner.TagName
    WHERE P_UserTags.OwnerUserId = U.Id
      AND P_UserTags.PostTypeId = 1
      AND P_UserTags.Tags IS NOT NULL
      AND P_UserTags.Tags != ''
    GROUP BY TPM_Inner.TagName, TPM_Inner.AverageQuestionScoreForTag, TPM_Inner.TagPopularityRank
    ORDER BY SUM(P_UserTags.Score) DESC, COUNT(P_UserTags.Id) DESC
    LIMIT 1
) TPM ON TRUE -- LATERAL join always returns true and correlates with U
WHERE
    U.Reputation > 1000 -- Filter for more active users
    AND U.DisplayName IS NOT NULL
    AND U.LastAccessDate IS NOT NULL
    AND U.Location IS DISTINCT FROM 'Unknown' -- Exclude users with 'Unknown' location from main analysis
ORDER BY ReputationDecile, U.Reputation DESC, U.CreationDate ASC
LIMIT 1000;
