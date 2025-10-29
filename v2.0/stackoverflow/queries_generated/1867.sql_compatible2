WITH UserActivityMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COALESCE(SUM(P.Score), 0) AS TotalScoreOnOwnedPosts,
        AVG(CASE WHEN P.PostTypeId IN (1,2) THEN P.Score ELSE NULL END) AS AvgScorePerQuestionAnswer,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING U.Reputation > 5000 AND COUNT(DISTINCT P.Id) > 10 AND COUNT(DISTINCT C.Id) > 5
),
PostVoteAggregates AS (
    SELECT
        P.Id AS PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCountTotal,
        SUM(CASE WHEN V.VoteTypeId IN (8, 9) THEN V.BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY P.Id
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseEventCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenEventCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteEventCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (14, 15, 19, 20) THEN 1 ELSE 0 END) AS ModeratorActionCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN PH.CreationDate ELSE NULL END) AS LatestModerationActionDate,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        NULL AS LatestHistoryComment
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 33, 34)
    GROUP BY PH.PostId
),
PostHistoryLatestComment AS (
    SELECT ph2.PostId,
           ph2.Comment AS LatestHistoryComment
    FROM PostHistory ph2
    JOIN (
        SELECT PostId, MAX(CreationDate) AS MaxCreationDate
        FROM PostHistory
        WHERE PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 33, 34)
          AND NULLIF(Comment, '') IS NOT NULL
        GROUP BY PostId
    ) mx ON ph2.PostId = mx.PostId AND ph2.CreationDate = mx.MaxCreationDate
),
ControversialPostMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Title,
        P.Body,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.Score AS InitialScore,
        P.ViewCount,
        P.CommentCount,
        P.AcceptedAnswerId,
        PVA.UpvoteCount,
        PVA.DownvoteCount,
        COALESCE(PHA.CloseEventCount, 0) AS CloseEventCount,
        COALESCE(PHA.ReopenEventCount, 0) AS ReopenEventCount,
        COALESCE(PHA.DeleteEventCount, 0) AS DeleteEventCount,
        COALESCE(PHA.ModeratorActionCount, 0) AS ModeratorActionCount,
        COALESCE(PHA.LatestModerationActionDate, P.LastActivityDate) AS EffectiveLastActivity,
        (CAST(COALESCE(PVA.DownvoteCount, 0) AS NUMERIC) * 3
        + COALESCE(PHA.CloseEventCount, 0) * 5
        + COALESCE(PHA.ReopenEventCount, 0) * 2
        + COALESCE(PHA.DeleteEventCount, 0) * 10
        + COALESCE(P.CommentCount, 0) * 0.5
        + COALESCE(LENGTH(P.Body), 0) / 1000.0
        ) / (CAST(COALESCE(PVA.UpvoteCount, 0) AS NUMERIC) + 1.0 + COALESCE(PVA.FavoriteCountTotal, 0) * 0.5) AS ControversyScore,
        CASE
            WHEN P.ClosedDate IS NOT NULL AND COALESCE(PHA.DeleteEventCount, 0) > 0 THEN 'ClosedAndDeleted'
            WHEN P.ClosedDate IS NOT NULL AND COALESCE(PHA.ReopenEventCount, 0) > 0 THEN 'ClosedAndReopened'
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN COALESCE(PHA.DeleteEventCount, 0) > 0 THEN 'Deleted'
            WHEN COALESCE(PVA.DownvoteCount, 0) > COALESCE(PVA.UpvoteCount, 0) * 2 AND COALESCE(PVA.UpvoteCount, 0) > 5 THEN 'HighlyDownvoted'
            WHEN COALESCE(P.FavoriteCount, 0) > 100 AND COALESCE(PVA.DownvoteCount, 0) > 50 THEN 'PopularButDivisive'
            ELSE 'NormalEngagement'
        END AS ControversyStatus,
        DENSE_RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY
            CASE
                WHEN P.ClosedDate IS NOT NULL THEN 1000
                WHEN COALESCE(PHA.DeleteEventCount, 0) > 0 THEN 900
                WHEN COALESCE(PHA.CloseEventCount, 0) > 0 THEN 800
                ELSE 0
            END DESC,
            (CAST(COALESCE(PVA.DownvoteCount, 0) AS NUMERIC) * 3
            + COALESCE(PHA.CloseEventCount, 0) * 5
            + COALESCE(PHA.ReopenEventCount, 0) * 2
            + COALESCE(PHA.DeleteEventCount, 0) * 10
            + COALESCE(P.CommentCount, 0) * 0.5
            + COALESCE(LENGTH(P.Body), 0) / 1000.0
            ) / (CAST(COALESCE(PVA.UpvoteCount, 0) AS NUMERIC) + 1.0 + COALESCE(PVA.FavoriteCountTotal, 0) * 0.5) DESC,
            ABS(COALESCE(PVA.UpvoteCount,0) - COALESCE(PVA.DownvoteCount,0)) DESC,
            (COALESCE(P.Score, 0) * -1) DESC
        ) AS PostControversyRank
    FROM Posts P
    LEFT JOIN PostVoteAggregates PVA ON P.Id = PVA.PostId
    LEFT JOIN PostHistoryAggregates PHA ON P.Id = PHA.PostId
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1, 2)
),
BadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN LOWER(B.Name) LIKE '%editor%' THEN 1 ELSE 0 END) AS HasEditorBadge,
        MAX(CASE WHEN LOWER(B.Name) LIKE '%reviewer%' OR LOWER(B.Name) LIKE '%moderator%' THEN 1 ELSE 0 END) AS HasReviewerOrModeratorBadge
    FROM Badges B
    GROUP BY B.UserId
),
RelatedPostLinkSummary AS (
    SELECT
        PL.PostId,
        STRING_AGG(
            CASE
                WHEN LT.Name = 'Linked' THEN 'L:' || CAST(PL.RelatedPostId AS TEXT)
                WHEN LT.Name = 'Duplicate' THEN 'D:' || CAST(PL.RelatedPostId AS TEXT)
                ELSE 'O:' || CAST(PL.RelatedPostId AS TEXT)
            END, '; ' ORDER BY LT.Name, PL.RelatedPostId
        ) AS RelatedPostsDescription,
        COUNT(DISTINCT CASE WHEN LT.Name = 'Duplicate' THEN PL.RelatedPostId ELSE NULL END) AS DuplicateLinkCount,
        MAX(CASE WHEN EXISTS (
            SELECT 1 FROM ControversialPostMetrics CPM_INNER
            WHERE CPM_INNER.PostId = PL.RelatedPostId
            AND CPM_INNER.ControversyScore > 15.0
        ) THEN 1 ELSE 0 END) AS HasHighlyControversialRelatedPost
    FROM PostLinks PL
    JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    GROUP BY PL.PostId
)
SELECT
    UAM.UserId,
    UAM.DisplayName,
    UAM.Reputation,
    UAM.UserCreationDate,
    UAM.LastAccessDate,
    UAM.TotalPostsOwned,
    UAM.TotalQuestionsOwned,
    UAM.TotalAnswersOwned,
    UAM.TotalScoreOnOwnedPosts,
    UAM.AvgScorePerQuestionAnswer,
    UAM.LastPostActivityDate,
    BS.TotalBadges,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.HasEditorBadge,
    BS.HasReviewerOrModeratorBadge,
    CPM.PostId AS MostControversialPostId,
    CPM.Title AS MostControversialPostTitle,
    CPM.PostCreationDate AS MostControversialPostDate,
    CPM.ControversyScore,
    CPM.ControversyStatus,
    CPM.UpvoteCount AS ControversialPostUpvotes,
    CPM.DownvoteCount AS ControversialPostDownvotes,
    CPM.CloseEventCount AS ControversialPostCloseEvents,
    CPM.ReopenEventCount AS ControversialPostReopenEvents,
    CPM.DeleteEventCount AS ControversialPostDeleteEvents,
    CPM.ModeratorActionCount AS ControversialPostModeratorActions,
    (COALESCE(LENGTH(CPM.Body), 0) - COALESCE(LENGTH(REPLACE(COALESCE(CPM.Body, ''), ' ', '')), 0) + 1) AS ControversialPostBodyWordCount,
    NULLIF(TRIM(SUBSTRING(CPM.Tags FROM POSITION('<' IN COALESCE(CPM.Tags, '')) + 1 FOR POSITION('>' IN COALESCE(CPM.Tags, '')) - POSITION('<' IN COALESCE(CPM.Tags, '')) - 1)), '') AS FirstTagOfControversialPost,
    RPLS.RelatedPostsDescription,
    RPLS.DuplicateLinkCount,
    RPLS.HasHighlyControversialRelatedPost,
    COALESCE(UAM.DisplayName, 'Community User ' || CAST(UAM.UserId AS TEXT)) AS UserDisplayNameCoalesced,
    CASE
        WHEN UAM.Reputation > 75000 AND COALESCE(BS.GoldBadges,0) >= 10 AND COALESCE(BS.HasReviewerOrModeratorBadge,0) = 1 THEN 'Esteemed Veteran & Moderator'
        WHEN UAM.Reputation > 25000 AND COALESCE(BS.GoldBadges,0) >= 3 AND COALESCE(BS.HasEditorBadge,0) = 1 AND CPM.ControversyStatus = 'HighlyDownvoted' THEN 'Active but Controversial Contributor'
        WHEN UAM.Reputation > 10000 AND COALESCE(CPM.ControversyScore,0) > 20.0 AND CPM.ControversyStatus IN ('Closed', 'Deleted') THEN 'High-Reputation Controversial'
        WHEN UAM.TotalQuestionsOwned = 0 AND UAM.TotalAnswersOwned > 50 THEN 'Answer Specialist'
        ELSE 'General Active User'
    END AS UserEngagementCategory,
    (SELECT COUNT(C.Id) FROM Comments C WHERE C.PostId = CPM.PostId AND C.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')) AS RecentCommentsOnControversialPost,
    RANK() OVER (ORDER BY UAM.Reputation DESC, UAM.TotalPostsOwned DESC, COALESCE(BS.GoldBadges,0) DESC, COALESCE(CPM.ControversyScore,0) DESC) AS OverallUserRank,
    AVG(COALESCE(CPM.ControversyScore,0)) OVER (PARTITION BY (CASE
        WHEN UAM.Reputation > 75000 THEN 'Elite'
        WHEN UAM.Reputation > 25000 THEN 'High'
        ELSE 'Mid'
    END)) AS AvgControversyScoreInUserReputationTier,
    EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - UAM.UserCreationDate)) AS DaysSinceUserCreation,
    (LOWER(COALESCE(CPM.Title, '')) LIKE '%problem%' OR LOWER(COALESCE(CPM.Title, '')) LIKE '%issue%' OR POSITION('bug' IN LOWER(COALESCE(CPM.Title, ''))) > 0) AS TitleSuggestsProblematicContent
FROM UserActivityMetrics UAM
LEFT JOIN BadgeSummary BS ON UAM.UserId = BS.UserId
LEFT JOIN ControversialPostMetrics CPM ON UAM.UserId = CPM.OwnerUserId AND CPM.PostControversyRank = 1
LEFT JOIN RelatedPostLinkSummary RPLS ON CPM.PostId = RPLS.PostId
LEFT JOIN PostHistoryLatestComment phlc ON CPM.PostId = phlc.PostId
WHERE CPM.PostId IS NOT NULL
  AND CPM.ControversyScore > 10.0
  AND EXISTS (
      SELECT 1 FROM PostHistoryAggregates PHA_inner
      WHERE PHA_inner.PostId = CPM.PostId
      AND (PHA_inner.CloseEventCount > 0 OR PHA_inner.DeleteEventCount > 0 OR PHA_inner.ModeratorActionCount > 0)
  )
  AND (UAM.LastAccessDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months') OR UAM.Reputation > 50000)
ORDER BY OverallUserRank ASC, UAM.Reputation DESC, CPM.ControversyScore DESC
LIMIT 500;