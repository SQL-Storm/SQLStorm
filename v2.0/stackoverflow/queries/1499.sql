WITH UserPostStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionCount,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END), 0) AS TotalQuestionScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END), 0.0) AS AvgQuestionScore,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END), 0) AS TotalQuestionViews,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswerCount,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END), 0) AS TotalAnswerScore,
        COALESCE(AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END), 0.0) AS AvgAnswerScore,
        COALESCE(AVG(P.Score), 0.0) AS UserOverallAvgPostScore,
        COALESCE(COUNT(P.Id), 0) AS TotalPosts
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1, 2)
    GROUP BY P.OwnerUserId
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN V.VoteTypeId IN (2, 8) THEN 1 ELSE 0 END), 0) AS UpvoteCount,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCount,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END), 0) AS EditRollbackHistoryCount,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END), 0) AS ReopenCount,
        COALESCE(SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0) AS CloseCount,
        MAX(P.LastActivityDate) AS PostLastActivity
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadgeCount,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadgeCount,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadgeCount
    FROM Badges B
    GROUP BY B.UserId
),
TagPerformanceGlobal AS (
    SELECT
        TRIM(tag) AS TagName,
        SUM(P.Score) AS TagTotalScore,
        AVG(P.Score) AS TagAvgScore,
        COUNT(P.Id) AS TagPostCount
    FROM Posts P,
         LATERAL (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS tag) t
    WHERE P.Tags IS NOT NULL AND P.PostTypeId = 1
    GROUP BY TRIM(tag)
    HAVING COUNT(P.Id) > 50
),
LinkedPostSummary AS (
    SELECT
        PL.PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalLinkedPostCount,
        SUM(CASE WHEN LT.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount,
        MAX(P_Related.LastActivityDate) AS LastActivityOfRelatedPosts
    FROM PostLinks PL
    JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    JOIN Posts P_Related ON PL.RelatedPostId = P_Related.Id
    GROUP BY PL.PostId
),
PostCloseReasonSummary AS (
    SELECT
        PH_Inner.PostId,
        STRING_AGG(DISTINCT CRT.Name, '; ' ORDER BY CRT.Name) AS CloseReasonsEncountered
    FROM PostHistory PH_Inner
    JOIN CloseReasonTypes CRT ON PH_Inner.Comment = CAST(CRT.Id AS TEXT)
    WHERE PH_Inner.PostHistoryTypeId = 10
    GROUP BY PH_Inner.PostId
),
TopPostsPerUser AS (
    SELECT
        P_Inner.Id AS PostId,
        P_Inner.OwnerUserId,
        P_Inner.Title AS TopPostTitle,
        P_Inner.Score AS TopPostScore,
        ROW_NUMBER() OVER (PARTITION BY P_Inner.OwnerUserId ORDER BY P_Inner.Score DESC, P_Inner.ViewCount DESC) AS RankNum
    FROM Posts P_Inner
    WHERE P_Inner.PostTypeId IN (1, 2) AND P_Inner.Score > 0
),
TopPostsPerUserAggregated AS (
    SELECT
        OwnerUserId AS UserId,
        MAX(CASE WHEN RankNum = 1 THEN TopPostTitle END) AS Top1PostTitle,
        MAX(CASE WHEN RankNum = 1 THEN TopPostScore END) AS Top1PostScore,
        MAX(CASE WHEN RankNum = 2 THEN TopPostTitle END) AS Top2PostTitle,
        MAX(CASE WHEN RankNum = 2 THEN TopPostScore END) AS Top2PostScore,
        MAX(CASE WHEN RankNum = 3 THEN TopPostTitle END) AS Top3PostTitle,
        MAX(CASE WHEN RankNum = 3 THEN TopPostScore END) AS Top3PostScore
    FROM TopPostsPerUser
    GROUP BY OwnerUserId
),
PostContextualAvgScore AS (
    SELECT
        P_Base.Id AS PostId,
        (
            SELECT COALESCE(AVG(P_Other.Score), 0.0)
            FROM Posts P_Other
            WHERE P_Other.OwnerUserId = P_Base.OwnerUserId
              AND P_Other.Id != P_Base.Id
              AND P_Other.CreationDate BETWEEN P_Base.CreationDate - INTERVAL '30 days' AND P_Base.CreationDate + INTERVAL '30 days'
              AND P_Other.PostTypeId IN (1,2)
        ) AS AvgOtherPostsScoreNearThisPost
    FROM Posts P_Base
    WHERE P_Base.PostTypeId IN (1, 2)
),
ModeratorPostActivity AS (
    SELECT PH.PostId, PH.UserId AS ActorUserId, PH.CreationDate, 'Moderator' AS ActorType, 'History' AS SourceType
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (14, 15, 19, 20)
    UNION ALL
    SELECT V.PostId, V.UserId AS ActorUserId, V.CreationDate, 'Moderator' AS ActorType, 'Vote' AS SourceType
    FROM Votes V
    WHERE V.VoteTypeId IN (14, 15)
),
UserPostActivity AS (
    SELECT PH.PostId, PH.UserId AS ActorUserId, PH.CreationDate, 'User' AS ActorType, 'History' AS SourceType
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
    UNION ALL
    SELECT V.PostId, V.UserId AS ActorUserId, V.CreationDate, 'User' AS ActorType, 'Vote' AS SourceType
    FROM Votes V
    WHERE V.VoteTypeId IN (2, 3, 5)
),
AllPostActivityAggregated AS (
    SELECT
        PostId,
        COUNT(DISTINCT ActorUserId) AS DistinctActors,
        COUNT(CASE WHEN ActorType = 'Moderator' THEN 1 END) AS TotalModeratorActions,
        COUNT(CASE WHEN ActorType = 'User' THEN 1 END) AS TotalUserActions,
        MAX(CreationDate) AS LatestActivityDate
    FROM (
        SELECT * FROM ModeratorPostActivity
        UNION ALL
        SELECT * FROM UserPostActivity
    ) AS CombinedActivities
    GROUP BY PostId
),
UserTagContributions AS (
    SELECT
        P.OwnerUserId AS UserId,
        STRING_AGG(DISTINCT TRIM(tag), ', ' ORDER BY TRIM(tag)) AS ContributedTags
    FROM Posts P,
         LATERAL (SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS tag) t
    WHERE P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND P.PostTypeId = 1
    GROUP BY P.OwnerUserId
),
UserPostAggregates AS (
    SELECT
        P.OwnerUserId AS UserId,
        COALESCE(SUM(PEM.CommentCount), 0) AS TotalCommentsOnUserPosts,
        COALESCE(SUM(PEM.UpvoteCount), 0) AS TotalUpvotesOnUserPosts,
        COALESCE(SUM(PEM.DownvoteCount), 0) AS TotalDownvotesOnUserPosts,
        COALESCE(SUM(PEM.EditRollbackHistoryCount), 0) AS TotalEditRollbacksOnUserPosts,
        COALESCE(SUM(PEM.ReopenCount), 0) AS TotalReopensOnUserPosts,
        COALESCE(SUM(PEM.CloseCount), 0) AS TotalClosesOnUserPosts,
        COALESCE(AVG(LPS.TotalLinkedPostCount), 0.0) AS AvgLinkedPostsPerUserPost,
        COALESCE(SUM(LPS.DuplicateLinkCount), 0) AS TotalDuplicateLinksToUserPosts,
        COALESCE(STRING_AGG(DISTINCT PCS.CloseReasonsEncountered, ' | ' ORDER BY PCS.CloseReasonsEncountered), 'No closed posts') AS UserPostsCloseReasons,
        COALESCE(AVG(PCAS.AvgOtherPostsScoreNearThisPost), 0.0) AS UserAvgContextualScore,
        COALESCE(SUM(APA.TotalModeratorActions), 0) AS TotalModActionsOnUserPosts,
        COALESCE(SUM(APA.TotalUserActions), 0) AS TotalUserActionsOnUserPosts,
        COALESCE(MAX(APA.LatestActivityDate), NULL) AS UserAndPostLatestActivity
    FROM Posts P
    JOIN PostEngagementMetrics PEM ON P.Id = PEM.PostId
    LEFT JOIN LinkedPostSummary LPS ON P.Id = LPS.PostId
    LEFT JOIN PostCloseReasonSummary PCS ON P.Id = PCS.PostId
    LEFT JOIN PostContextualAvgScore PCAS ON P.Id = PCAS.PostId
    LEFT JOIN AllPostActivityAggregated APA ON P.Id = APA.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.Views AS UserProfileViews,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate AS UserLastAccessDate,
    COALESCE(U.WebsiteUrl, '') AS UserWebsite,
    COALESCE(NULLIF(U.Location, ''), 'Unknown Location') AS UserLocation,
    COALESCE(UPS.QuestionCount, 0) AS TotalQuestionsAsked,
    COALESCE(UPS.TotalQuestionScore, 0) AS SumOfQuestionScores,
    COALESCE(UPS.AvgQuestionScore, 0.0) AS AverageQuestionScore,
    COALESCE(UPS.TotalQuestionViews, 0) AS SumOfQuestionViews,
    COALESCE(UPS.AnswerCount, 0) AS TotalAnswersGiven,
    COALESCE(UPS.TotalAnswerScore, 0) AS SumOfAnswerScores,
    COALESCE(UPS.AvgAnswerScore, 0.0) AS AverageAnswerScore,
    COALESCE(UPS.UserOverallAvgPostScore, 0.0) AS OverallAvgPostScore,
    COALESCE(UBS.GoldBadgeCount, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadgeCount, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadgeCount, 0) AS BronzeBadges,
    TPA.Top1PostTitle,
    TPA.Top1PostScore,
    TPA.Top2PostTitle,
    TPA.Top2PostScore,
    TPA.Top3PostTitle,
    TPA.Top3PostScore,
    COALESCE(UPA.TotalCommentsOnUserPosts, 0) AS TotalCommentsOnUserPosts,
    COALESCE(UPA.TotalUpvotesOnUserPosts, 0) AS TotalUpvotesOnUserPosts,
    COALESCE(UPA.TotalDownvotesOnUserPosts, 0) AS TotalDownvotesOnUserPosts,
    COALESCE(UPA.TotalEditRollbacksOnUserPosts, 0) AS TotalEditRollbacksOnUserPosts,
    COALESCE(UPA.TotalReopensOnUserPosts, 0) AS TotalReopensOnUserPosts,
    COALESCE(UPA.TotalClosesOnUserPosts, 0) AS TotalClosesOnUserPosts,
    COALESCE(UPA.AvgLinkedPostsPerUserPost, 0.0) AS AvgLinkedPostsPerUserPost,
    COALESCE(UPA.TotalDuplicateLinksToUserPosts, 0) AS TotalDuplicateLinksToUserPosts,
    COALESCE(UPA.UserPostsCloseReasons, 'No closed posts') AS UserPostsCloseReasons,
    COALESCE(UPA.UserAvgContextualScore, 0.0) AS UserAvgContextualScore,
    CASE
        WHEN U.AboutMe ILIKE '%database%' OR U.AboutMe ILIKE '%sql%' OR U.DisplayName ILIKE '%DBA%' THEN 'Database Specialist'
        WHEN U.AboutMe ILIKE '%front-end%' OR U.AboutMe ILIKE '%javascript%' OR U.DisplayName ILIKE '%frontend%' THEN 'Frontend Developer'
        WHEN U.AboutMe IS NULL OR TRIM(U.AboutMe) = '' THEN 'No About Me Description'
        ELSE 'General Developer'
    END AS UserProfileType,
    COALESCE(UTC.ContributedTags, 'No Tags') AS UserContributedTags,
    COALESCE(UPA.TotalModActionsOnUserPosts, 0) AS TotalModActionsOnUserPosts,
    COALESCE(UPA.TotalUserActionsOnUserPosts, 0) AS TotalUserActionsOnUserPosts,
    COALESCE(UPA.UserAndPostLatestActivity, U.LastAccessDate) AS EffectiveLastActivity
FROM Users U
LEFT JOIN UserPostStats UPS ON U.Id = UPS.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN TopPostsPerUserAggregated TPA ON U.Id = TPA.UserId
LEFT JOIN UserPostAggregates UPA ON U.Id = UPA.UserId
LEFT JOIN UserTagContributions UTC ON U.Id = UTC.UserId
ORDER BY U.Reputation DESC, U.Id;