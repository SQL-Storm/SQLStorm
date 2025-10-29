WITH UserRecentActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.Views AS UserProfileViews,
        U.Location,
        U.AboutMe,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        MIN(COALESCE(P.CreationDate, C.CreationDate, V.CreationDate)) AS FirstRecordedActivityDate,
        MAX(COALESCE(P.CreationDate, C.CreationDate, V.CreationDate)) AS LastRecordedActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.Location, U.AboutMe
    HAVING U.LastAccessDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 year')
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.Tags,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        (P.Score * 0.5 + COALESCE(P.ViewCount, 0) * 0.1 + COALESCE(P.AnswerCount, 0) * 0.8 + COALESCE(P.FavoriteCount, 0) * 1.5) AS EngagementScore,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC, P.CreationDate DESC) AS PostTypeScoreRank
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.Tags
),
UserPostContributions AS (
    SELECT
        PEM.OwnerUserId AS UserId,
        COUNT(PEM.PostId) AS TotalPostsOwned,
        SUM(PEM.Score) AS TotalPostScore,
        AVG(PEM.ViewCount) AS AvgPostViewCount,
        SUM(CASE WHEN PEM.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN PEM.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        SUM(CASE WHEN PEM.EngagementScore > 75 AND PEM.PostTypeScoreRank <= 1000 THEN 1 ELSE 0 END) AS HighEngagementTopRankPostsCount,
        SUM(PEM.UpvotesReceived) AS TotalUpvotesReceivedOnPosts,
        SUM(PEM.DownvotesReceived) AS TotalDownvotesReceivedOnPosts,
        STRING_AGG(DISTINCT TaggedPosts.Tag, ';' ORDER BY TaggedPosts.Tag) AS ContributedTags
    FROM PostEngagementMetrics PEM
    LEFT JOIN LATERAL (
        SELECT SUBSTRING(t_unnested FROM 2 FOR CHAR_LENGTH(t_unnested) - 1) AS Tag
        FROM UNNEST(string_to_array(SUBSTRING(PEM.Tags FROM 2 FOR CHAR_LENGTH(PEM.Tags) - 2), '><')) AS t_unnested(t_unnested)
        WHERE PEM.Tags IS NOT NULL AND CHAR_LENGTH(PEM.Tags) > 2
    ) AS TaggedPosts ON TRUE
    WHERE PEM.OwnerUserId IS NOT NULL
    GROUP BY PEM.OwnerUserId
),
ModerationInvolvement AS (
    SELECT
        PH.UserId,
        COUNT(DISTINCT PH.Id) AS TotalModerationActions,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS PostClosedEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS PostReopenedEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (12, 13) THEN 1 ELSE 0 END) AS PostDeleteUndeleteEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (19, 20) THEN 1 ELSE 0 END) AS QuestionProtectUnprotectEvents,
        MAX(PH.CreationDate) AS LastModerationActionDate,
        MIN(PH.CreationDate) AS FirstModerationActionDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 19, 20, 24, 33, 34)
      AND PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
BadgeDiversityAndConsistency AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadgesAwarded,
        COUNT(DISTINCT B.Name) AS UniqueBadgesCount,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        MAX(B.Date) AS LastBadgeAwardDate,
        MIN(B.Date) AS FirstBadgeAwardDate,
        EXISTS (SELECT 1 FROM Badges B_inner WHERE B_inner.UserId = B.UserId AND B_inner.Name = 'Fanatic' AND B_inner.Class = 1) AS HasFanaticBadge,
        EXISTS (SELECT 1 FROM Badges B_inner WHERE B_inner.UserId = B.UserId AND B_inner.Name LIKE '%Tag%Master%' AND B_inner.Class = 1) AS HasTagMasterBadge
    FROM Badges B
    GROUP BY B.UserId
),
PostLinkSummary AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT PL.PostId) AS PostsInvolvingLinks,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS OutgoingLinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS OutgoingDuplicateLinksCount,
        SUM(CASE WHEN PL.LinkTypeId = 1 AND P_Related.Score >= 10 AND P_Related.PostTypeId = 1 THEN 1 ELSE 0 END) AS LinksToHighScoreQuestions
    FROM PostLinks PL
    JOIN Posts P ON PL.PostId = P.Id
    LEFT JOIN Posts P_Related ON PL.RelatedPostId = P_Related.Id
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserCommunityTrustSignal AS (
    SELECT UserId FROM ModerationInvolvement WHERE PostDeleteUndeleteEvents > 0
    UNION
    SELECT P_Answer.OwnerUserId AS UserId
    FROM Posts P_Question
    JOIN Posts P_Answer ON P_Question.AcceptedAnswerId = P_Answer.Id
    WHERE P_Question.AcceptedAnswerId IS NOT NULL AND P_Answer.OwnerUserId IS NOT NULL
)
SELECT
    URA.UserId,
    URA.DisplayName,
    URA.Reputation,
    URA.Location,
    URA.UserProfileViews,
    COALESCE(UPC.TotalPostsOwned, 0) AS UserTotalPostsOwned,
    COALESCE(UPC.TotalQuestionsOwned, 0) AS UserTotalQuestions,
    COALESCE(UPC.TotalAnswersOwned, 0) AS UserTotalAnswers,
    COALESCE(UPC.TotalPostScore, 0) AS UserAggregatedPostScore,
    COALESCE(UPC.AvgPostViewCount, 0) AS UserAvgPostViews,
    COALESCE(UPC.HighEngagementTopRankPostsCount, 0) AS UserHighEngagementPosts,
    COALESCE(UPC.TotalUpvotesReceivedOnPosts, 0) AS UserUpvotesReceivedOnPosts,
    COALESCE(URA.TotalUpvotesGiven, 0) AS UserUpvotesGiven,
    UPC.ContributedTags,
    COALESCE(MI.TotalModerationActions, 0) AS UserTotalModerationActions,
    COALESCE(MI.PostClosedEvents, 0) AS UserPostClosedEvents,
    COALESCE(BDC.GoldBadgesCount, 0) AS UserGoldBadges,
    COALESCE(BDC.SilverBadgesCount, 0) AS UserSilverBadges,
    COALESCE(BDC.BronzeBadgesCount, 0) AS UserBronzeBadges,
    BDC.HasFanaticBadge,
    BDC.HasTagMasterBadge,
    COALESCE(PLS.PostsInvolvingLinks, 0) AS UserPostsWithLinks,
    COALESCE(PLS.OutgoingDuplicateLinksCount, 0) AS UserOutgoingDuplicateLinks,
    COALESCE(PLS.LinksToHighScoreQuestions, 0) AS UserLinksToHighScoreQuestions,
    DENSE_RANK() OVER (ORDER BY (URA.TotalPostsCreated + URA.TotalCommentsMade) DESC, URA.Reputation DESC) AS ActivityRank,
    NTILE(5) OVER (ORDER BY URA.Reputation DESC) AS ReputationQuintile,
    (
        (URA.Reputation * 0.05) +
        (COALESCE(UPC.TotalPostScore, 0) * 0.2) +
        (COALESCE(UPC.TotalUpvotesReceivedOnPosts, 0) * 0.3) -
        (COALESCE(UPC.TotalDownvotesReceivedOnPosts, 0) * 0.5) +
        (COALESCE(URA.TotalUpvotesGiven, 0) * 0.1) +
        (COALESCE(MI.TotalModerationActions, 0) * 1.5) +
        (COALESCE(BDC.GoldBadgesCount, 0) * 10) +
        (COALESCE(BDC.SilverBadgesCount, 0) * 3) +
        (COALESCE(URA.UserProfileViews, 0) * 0.001) +
        (COALESCE(PLS.LinksToHighScoreQuestions, 0) * 0.8)
    ) AS UserImpactScore,
    CASE
        WHEN URA.Location IS NULL OR TRIM(URA.Location) = '' THEN 'Unspecified'
        WHEN UPPER(URA.Location) LIKE '%LONDON%' OR UPPER(URA.Location) LIKE '%NEW YORK%' OR UPPER(URA.Location) LIKE '%SAN FRANCISCO%' THEN 'Global Tech Hub'
        WHEN UPPER(URA.Location) LIKE '%INDIA%' OR UPPER(URA.Location) LIKE '%EUROPE%' OR UPPER(URA.Location) LIKE '%ASIA%' THEN 'Regional Contributor'
        ELSE 'Other Location'
    END AS DetailedLocationCategory,
    CASE
        WHEN URA.AboutMe IS NULL OR TRIM(URA.AboutMe) = '' THEN 'No Bio'
        WHEN CHAR_LENGTH(URA.AboutMe) < 50 THEN 'Short Bio'
        WHEN CHAR_LENGTH(URA.AboutMe) BETWEEN 50 AND 200 THEN 'Medium Bio'
        ELSE 'Detailed Bio'
    END AS AboutMeBioStatus,
    EXISTS (
        SELECT 1
        FROM Comments C_inner
        JOIN Posts P_inner ON C_inner.PostId = P_inner.Id
        WHERE C_inner.UserId = URA.UserId
          AND P_inner.PostTypeId = 1
          AND COALESCE(P_inner.FavoriteCount, 0) > 50
          AND C_inner.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '6 months')
        LIMIT 1
    ) AS CommentedOnPopularQuestionRecently,
    DATE_PART('day', URA.UserLastAccessDate - URA.UserCreationDate) AS UserTenureDays,
    CASE WHEN UCTS.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS HasCommunityTrustSignal
FROM UserRecentActivity URA
LEFT JOIN UserPostContributions UPC ON URA.UserId = UPC.UserId
LEFT JOIN ModerationInvolvement MI ON URA.UserId = MI.UserId
LEFT JOIN BadgeDiversityAndConsistency BDC ON URA.UserId = BDC.UserId
LEFT JOIN PostLinkSummary PLS ON URA.UserId = PLS.UserId
LEFT JOIN UserCommunityTrustSignal UCTS ON URA.UserId = UCTS.UserId
WHERE URA.Reputation > 500
  AND URA.TotalPostsCreated >= 10
  AND (COALESCE(UPC.TotalQuestionsOwned, 0) + COALESCE(UPC.TotalAnswersOwned, 0)) > 5
  AND (
        (COALESCE(BDC.GoldBadgesCount, 0) >= 1 AND COALESCE(MI.TotalModerationActions, 0) >= 3)
        OR
        (URA.TotalUpvotesGiven > 200 AND COALESCE(UPC.TotalPostScore, 0) > 100 AND URA.Location IS NOT NULL AND TRIM(URA.Location) != '')
        OR
        (URA.Reputation > 10000 AND URA.DisplayName LIKE 'D%' AND COALESCE(PLS.LinksToHighScoreQuestions, 0) > 0)
        OR
        (UCTS.UserId IS NOT NULL AND URA.UserProfileViews > 1000)
  )
ORDER BY UserImpactScore DESC, URA.Reputation DESC, ActivityRank ASC
LIMIT 500;