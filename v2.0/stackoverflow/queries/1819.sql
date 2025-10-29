-- {"query": "1819.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2637}
WITH UserPostStats AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(Id) AS TotalPostsOwned,
        COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS TotalQuestionsOwned,
        COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS TotalAnswersOwned,
        SUM(Score) AS TotalPostScoreOwned,
        SUM(ViewCount) AS TotalPostViewCountOwned,
        SUM(AnswerCount) AS TotalAnswersReceivedOnQuestions,
        SUM(CommentCount) AS TotalCommentsReceivedOnPosts,
        SUM(FavoriteCount) AS TotalFavoriteCountReceivedOnPosts
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserCommentStats AS (
    SELECT
        UserId,
        COUNT(Id) AS TotalCommentsMade,
        SUM(Score) AS TotalCommentScoreMade
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserVoteStats AS (
    SELECT
        UserId,
        COUNT(Id) AS TotalVotesCast
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserReceivedVoteStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS ReceivedUpVotesOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS ReceivedDownVotesOnPosts
    FROM Posts P
    JOIN Votes V ON P.Id = V.PostId
    WHERE P.OwnerUserId IS NOT NULL AND V.VoteTypeId IN (2, 3)
    GROUP BY P.OwnerUserId
),
UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUpVotesGivenByBadges,
        U.DownVotes AS TotalDownVotesGivenByBadges,
        COALESCE(UPS.TotalPostsOwned, 0) AS TotalPostsOwned,
        COALESCE(UPS.TotalQuestionsOwned, 0) AS TotalQuestionsOwned,
        COALESCE(UPS.TotalAnswersOwned, 0) AS TotalAnswersOwned,
        COALESCE(UPS.TotalPostScoreOwned, 0) AS TotalPostScoreOwned,
        COALESCE(UPS.TotalPostViewCountOwned, 0) AS TotalPostViewCountOwned,
        COALESCE(UPS.TotalAnswersReceivedOnQuestions, 0) AS TotalAnswersReceivedOnQuestions,
        COALESCE(UPS.TotalCommentsReceivedOnPosts, 0) AS TotalCommentsReceivedOnPosts,
        COALESCE(UPS.TotalFavoriteCountReceivedOnPosts, 0) AS TotalFavoriteCountReceivedOnPosts,
        COALESCE(UCS.TotalCommentsMade, 0) AS TotalCommentsMade,
        COALESCE(UCS.TotalCommentScoreMade, 0) AS TotalCommentScoreMade,
        COALESCE(UVS.TotalVotesCast, 0) AS TotalVotesCast,
        COALESCE(URVS.ReceivedUpVotesOnPosts, 0) AS ReceivedUpVotesOnPosts,
        COALESCE(URVS.ReceivedDownVotesOnPosts, 0) AS ReceivedDownVotesOnPosts
    FROM Users U
    LEFT JOIN UserPostStats UPS ON U.Id = UPS.UserId
    LEFT JOIN UserCommentStats UCS ON U.Id = UCS.UserId
    LEFT JOIN UserVoteStats UVS ON U.Id = UVS.UserId
    LEFT JOIN UserReceivedVoteStats URVS ON U.Id = URVS.UserId
),
PostElaborateMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        P.ParentId,
        TRIM(BOTH '<>' FROM SUBSTRING(P.Tags FROM 1 FOR POSITION('>' IN P.Tags))) AS PrimaryTag,
        CAST(COALESCE(SUM(CASE WHEN C.Score > 0 THEN 1 ELSE 0 END), 0) AS NUMERIC) / NULLIF(COUNT(C.Id), 0) AS PositiveCommentRatio,
        (SELECT COUNT(DISTINCT C_Sub.UserId) FROM Comments C_Sub WHERE C_Sub.PostId = P.Id AND C_Sub.UserId IS NOT NULL) AS UniqueCommenters,
        (SELECT COUNT(PL_Sub.RelatedPostId) FROM PostLinks PL_Sub WHERE PL_Sub.PostId = P.Id AND PL_Sub.LinkTypeId = 3) AS DuplicateLinkCount,
        CASE WHEN P.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostScoreRankType,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS AvgOwnerPostScoreCumulative,
        CASE
            WHEN P.PostTypeId = 1 AND P.CreationDate < TIMESTAMP '2015-01-01' AND P.Score > 50 AND P.AnswerCount > 5 AND P.FavoriteCount > 10
            THEN 'High-Impact Old Question'
            WHEN P.PostTypeId = 2 AND P.CreationDate < TIMESTAMP '2015-01-01' AND P.Score > 75 AND P.Body LIKE '%<pre><code>%'
            THEN 'High-Quality Old Code Answer'
            ELSE 'Other Post'
        END AS PostImpactCategory,
        (SELECT COALESCE(SUM(A.Score), 0) FROM Posts A WHERE A.ParentId = P.Id AND A.PostTypeId = 2) AS SumOfAnswerScores,
        (SELECT A.Score FROM Posts A WHERE A.Id = P.AcceptedAnswerId) AS AcceptedAnswerScore,
        (SELECT COUNT(DISTINCT A.OwnerUserId) FROM Posts A WHERE A.ParentId = P.Id AND A.PostTypeId = 2 AND A.OwnerUserId IS NOT NULL) AS UniqueAnswererCount
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1, 2)
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.Title, P.Tags,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.Body, P.AcceptedAnswerId, P.ParentId
),
ModerationSummary AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE NULL END) AS DeleteEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 13 THEN 1 ELSE NULL END) AS UndeleteEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 14 THEN 1 ELSE NULL END) AS LockEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 15 THEN 1 ELSE NULL END) AS UnlockEvents,
        COUNT(DISTINCT PH.UserId) AS DistinctModeratorActioners,
        STRING_AGG(DISTINCT CRT.Name, '; ') AS DistinctCloseReasons
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND CAST(PH.Comment AS SMALLINT) = CRT.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY PH.PostId
)
SELECT
    'Question' AS RecordType,
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserProfileViews,
    UAS.TotalPostsOwned,
    UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned,
    UAS.TotalPostScoreOwned,
    UAS.TotalCommentsMade,
    UAS.TotalCommentScoreMade,
    UAS.ReceivedUpVotesOnPosts,
    UAS.ReceivedDownVotesOnPosts,
    (CAST(UAS.ReceivedUpVotesOnPosts AS NUMERIC) / NULLIF((UAS.ReceivedUpVotesOnPosts + UAS.ReceivedDownVotesOnPosts), 0)) AS NetUpvoteRatio,
    (CAST(UAS.TotalQuestionsOwned AS NUMERIC) / NULLIF(UAS.TotalPostsOwned, 0)) AS QuestionToPostRatio,
    DATE_PART('year', AGE(TIMESTAMP '2024-10-01 12:34:56', UAS.CreationDate)) AS YearsActive,
    PEM.PostId AS RelatedPostId,
    PEM.Title AS RelatedPostTitle,
    PEM.PostScore AS RelatedPostScore,
    PEM.PostViewCount AS RelatedPostViewCount,
    PEM.PrimaryTag AS Primary
FROM UserActivitySummary UAS
LEFT JOIN PostElaborateMetrics PEM ON UAS.UserId = PEM.OwnerUserId
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserProfileViews, UAS.TotalPostsOwned, UAS.TotalQuestionsOwned,
    UAS.TotalAnswersOwned, UAS.TotalPostScoreOwned, UAS.TotalCommentsMade, UAS.TotalCommentScoreMade,
    UAS.ReceivedUpVotesOnPosts, UAS.ReceivedDownVotesOnPosts, UAS.CreationDate,
    PEM.PostId, PEM.Title, PEM.PostScore, PEM.PostViewCount, PEM.PrimaryTag;