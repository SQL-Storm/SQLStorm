-- {"query": "1646.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3630}
WITH UserActivityMetrics AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anon-' || U.Id) AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreSum,
        AVG(COALESCE(P.ViewCount, 0)) AS AvgPostViewCount,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.LastAccessDate)) AS LatestActivityTimestamp,
        MIN(COALESCE(P.CreationDate, C.CreationDate, U.CreationDate)) AS EarliestActivityTimestamp,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersCount,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswersReceived,
        SUM(CASE WHEN P.ParentId IS NOT NULL AND P.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) AS AnswersAcceptedByOthers,
        LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeCharCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.AboutMe
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        LENGTH(COALESCE(P.Body, '')) AS BodyCharCount,
        LENGTH(COALESCE(P.Title, '')) AS TitleCharCount,
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN array_length(string_to_array(substring(P.Tags from 2 for length(P.Tags)-2), '><'), 1)
            ELSE 0
        END AS TagCount,
        COALESCE(P.LastEditDate, P.CreationDate) AS EffectiveLastEditDate,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6) AND PH.UserId IS NOT NULL) AS UserEditCount,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10 AND PH.Comment = '101') AS DuplicateCloseVotes
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= DATE '2020-01-01'
),
BadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeAwardDate,
        MIN(B.Date) AS EarliestBadgeAwardDate
    FROM Badges B
    GROUP BY B.UserId
),
VoteDistribution AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesOnPost,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesOnPost,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotesOnPost,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotesOnPost
    FROM Votes V
    WHERE V.VoteTypeId IN (1, 2, 3, 5)
    GROUP BY V.PostId
),
AggregatedRecentPostStats AS (
    SELECT
        PCA.OwnerUserId AS UserId,
        COUNT(PCA.PostId) AS TotalRecentPosts,
        SUM(PCA.PostScore) AS RecentPostsTotalScore,
        AVG(PCA.ViewCount) AS AvgRecentPostViews,
        MAX(PCA.BodyCharCount) AS MaxRecentPostBodyLength,
        MIN(PCA.TitleCharCount) AS MinRecentPostTitleLength,
        SUM(CASE WHEN PCA.TagCount > 3 THEN 1 ELSE 0 END) AS MultiTagPostsCount,
        SUM(PCA.UserEditCount) AS TotalUserEditsOnRecentPosts,
        SUM(PCA.DuplicateCloseVotes) AS TotalRecentDuplicateClosedPosts
    FROM PostContentAnalysis PCA
    GROUP BY PCA.OwnerUserId
)
SELECT
    'HighReputationUserSummary' AS MetricCategory,
    UAM.UserId,
    UAM.UserDisplayName,
    UAM.Reputation,
    UAM.UserCreationDate,
    UAM.LatestActivityTimestamp,
    UAM.TotalPostsOwned,
    UAM.QuestionsCount,
    UAM.AnswersCount,
    UAM.TotalCommentsMade,
    UAM.AvgPostViewCount,
    UAM.AcceptedAnswersReceived,
    COALESCE(BS.GoldBadges, 0) AS GoldBadges,
    COALESCE(BS.SilverBadges, 0) AS SilverBadges,
    COALESCE(BS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(APS.TotalRecentPosts, 0) AS TotalRecentPosts,
    COALESCE(APS.RecentPostsTotalScore, 0) AS RecentPostsTotalScore,
    (UAM.UserTotalUpVotes - UAM.UserTotalDownVotes) AS NetUserVotesLifetime,
    (CASE WHEN UAM.TotalPostsOwned > 0 THEN UAM.TotalPostScoreSum * 1.0 / UAM.TotalPostsOwned ELSE 0.0 END) AS AvgScorePerPostLifetime,
    UAM.LatestActivityTimestamp - UAM.EarliestActivityTimestamp AS TotalActivitySpan,
    NTILE(10) OVER (ORDER BY UAM.Reputation DESC, UAM.TotalPostsOwned DESC) AS ReputationPostDecile,
    LAG(UAM.LatestActivityTimestamp, 1, UAM.UserCreationDate) OVER (PARTITION BY UAM.UserId ORDER BY UAM.LatestActivityTimestamp) AS PreviousActivityTimestamp,
    (SELECT B2.Name FROM Badges B2 WHERE B2.UserId = UAM.UserId AND B2.Class = 1 ORDER BY B2.Date DESC LIMIT 1) AS LastGoldBadgeName,
    (SELECT COUNT(P2.Id)
     FROM Posts P2
     WHERE P2.OwnerUserId = UAM.UserId
       AND P2.PostTypeId = 1
       AND P2.CreationDate > UAM.UserCreationDate
       AND P2.Score > (SELECT AVG(P3.Score) FROM Posts P3 WHERE P3.PostTypeId = 1 AND P3.OwnerUserId = UAM.UserId)
    ) AS AboveAvgScoreQuestionsCount,
    (SELECT COUNT(DISTINCT PL.RelatedPostId)
     FROM PostLinks PL
     WHERE PL.PostId IN (SELECT PCA.PostId FROM PostContentAnalysis PCA WHERE PCA.OwnerUserId = UAM.UserId)
       AND PL.LinkTypeId = 3
    ) AS PostsLinkedAsDuplicateCount,
    UAM.UserProfileViews,
    UAM.UserTotalUpVotes,
    UAM.UserTotalDownVotes,
    APS.MaxRecentPostBodyLength,
    APS.MinRecentPostTitleLength,
    APS.MultiTagPostsCount,
    COALESCE(BS.LatestBadgeAwardDate, UAM.UserCreationDate) AS LastBadgeOrCreationDate,
    UAM.AboutMeCharCount,
    (SELECT COUNT(DISTINCT T.Id) FROM Tags T WHERE T.WikiPostId IN (SELECT P.Id FROM Posts P WHERE P.OwnerUserId = UAM.UserId)) AS TagsWithUserWikiContribution
FROM UserActivityMetrics UAM
LEFT JOIN BadgeSummary BS ON UAM.UserId = BS.UserId
LEFT JOIN AggregatedRecentPostStats APS ON UAM.UserId = APS.UserId
WHERE UAM.Reputation >= 5000
  AND UAM.TotalPostsOwned > 10
  AND UAM.LatestActivityTimestamp IS NOT NULL
  AND (UAM.LatestActivityTimestamp - UAM.UserCreationDate) > INTERVAL '2 year'
  AND (UAM.AboutMeCharCount > 0 OR UAM.UserTotalUpVotes > UAM.UserTotalDownVotes * 2)
  AND UAM.UserId % 3 = 0
  AND NOT EXISTS (
      SELECT 1 FROM Badges B_exclude WHERE B_exclude.UserId = UAM.UserId AND B_exclude.Name = 'Analyst'
  )
  AND UAM.UserId IN (SELECT DISTINCT PCA.OwnerUserId FROM PostContentAnalysis PCA WHERE PCA.ViewCount > 10000 AND PCA.PostTypeId = 1)

UNION ALL

SELECT
    'HighEngagementPostDetails' AS MetricCategory,
    PCA.OwnerUserId AS UserId,
    COALESCE(U.DisplayName, 'Deleted Post Owner ' || PCA.OwnerUserId) AS UserDisplayName,
    U.Reputation,
    PCA.PostCreationDate AS UserCreationDate,
    PCA.EffectiveLastEditDate AS LatestActivityTimestamp,
    1 AS TotalPostsOwned,
    CASE WHEN PCA.PostTypeId = 1 THEN 1 ELSE 0 END AS QuestionsCount,
    CASE WHEN PCA.PostTypeId = 2 THEN 1 ELSE 0 END AS AnswersCount,
    PCA.PostCommentCount AS TotalCommentsMade,
    PCA.ViewCount AS AvgPostViewCount,
    CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS AcceptedAnswersReceived,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    NULL AS TotalRecentPosts,
    NULL AS RecentPostsTotalScore,
    (COALESCE(VD.UpVotesOnPost, 0) - COALESCE(VD.DownVotesOnPost, 0)) AS NetUserVotesLifetime,
    PCA.PostScore * 1.0 AS AvgScorePerPostLifetime,
    PCA.EffectiveLastEditDate - PCA.PostCreationDate AS TotalActivitySpan,
    RANK() OVER (PARTITION BY PCA.PostTypeId ORDER BY PCA.PostScore DESC, PCA.ViewCount DESC) AS ReputationPostDecile,
    LEAD(PCA.EffectiveLastEditDate, 1, PCA.PostCreationDate) OVER (PARTITION BY PCA.OwnerUserId ORDER BY PCA.PostCreationDate) AS PreviousActivityTimestamp,
    NULL AS LastGoldBadgeName,
    (SELECT COUNT(C2.Id) FROM Comments C2 WHERE C2.PostId = PCA.PostId AND C2.Text LIKE '%solution%' AND C2.Score > 5) AS AboveAvgScoreQuestionsCount,
    (SELECT COUNT(DISTINCT PL.RelatedPostId)
     FROM PostLinks PL
     WHERE PL.PostId = PCA.PostId
       AND PL.LinkTypeId = 1
    ) AS PostsLinkedAsDuplicateCount,
    U.Views AS UserProfileViews,
    U.UpVotes AS UserTotalUpVotes,
    U.DownVotes AS UserTotalDownVotes,
    PCA.BodyCharCount AS MaxRecentPostBodyLength,
    PCA.TitleCharCount AS MinRecentPostTitleLength,
    PCA.TagCount AS MultiTagPostsCount,
    PCA.PostCreationDate AS LastBadgeOrCreationDate,
    LENGTH(COALESCE(P.Body, '')) AS AboutMeCharCount,
    (SELECT COUNT(DISTINCT T.Id) FROM Tags T JOIN Posts P4 ON T.ExcerptPostId = P4.Id WHERE P4.Id = PCA.PostId) AS TagsWithUserWikiContribution
FROM PostContentAnalysis PCA
INNER JOIN Users U ON PCA.OwnerUserId = U.Id
INNER JOIN Posts P ON PCA.PostId = P.Id
LEFT JOIN VoteDistribution VD ON PCA.PostId = VD.PostId
WHERE PCA.PostScore > 500
  AND PCA.ViewCount > 50000
  AND PCA.PostTypeId = 1
  AND PCA.ClosedDate IS NULL
  AND PCA.FavoriteCount IS NOT NULL
  AND (P.Body LIKE '%sql%' OR P.Title LIKE '%database%')
  AND PCA.PostId NOT IN (SELECT PH.PostId FROM PostHistory PH WHERE PH.PostHistoryTypeId = 12)
ORDER BY ReputationPostDecile ASC, LatestActivityTimestamp DESC
LIMIT 7500;