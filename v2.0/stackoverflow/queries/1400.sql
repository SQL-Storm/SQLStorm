-- {"query": "1400.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4539}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserViews,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Class) AS MaxBadgeClass,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (U.Reputation * 0.15) + (U.UpVotes * 0.08) - (U.DownVotes * 0.03) + (U.Views * 0.005) + (COUNT(DISTINCT B.Id) * 0.1) AS UserActivityScore,
        CASE
            WHEN U.Reputation >= 20000 AND EXISTS (SELECT 1 FROM Badges B_ WHERE B_.UserId = U.Id AND B_.Class = 1 AND B_.Date >= U.CreationDate + INTERVAL '1 year') THEN 'Legendary'
            WHEN U.Reputation >= 10000 AND U.UpVotes > 1000 AND U.Views > 5000 THEN 'Elite'
            WHEN U.Reputation >= 5000 OR (U.Reputation >= 2000 AND COUNT(DISTINCT B.Id) > 15 AND U.LastAccessDate > U.CreationDate + INTERVAL '1 year') THEN 'Advanced'
            WHEN U.Reputation >= 500 AND U.LastAccessDate > U.CreationDate + INTERVAL '3 months' THEN 'Intermediate'
            ELSE 'Novice'
        END AS ReputationTier,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM U.CreationDate) ORDER BY (U.UpVotes + U.DownVotes) DESC, U.Reputation DESC) AS RankInCreationYear,
        AVG(U.Reputation) OVER (PARTITION BY DATE_TRUNC('month', U.CreationDate)) AS AvgMonthlyCohortReputation
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE U.LastAccessDate >= U.CreationDate + INTERVAL '1 month'
      AND U.Reputation > 0
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views
),
PostCommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        MAX(C.CreationDate) AS LastCommentDate,
        MIN(C.CreationDate) AS FirstCommentDate,
        COUNT(DISTINCT C.UserId) AS DistinctCommenters,
        AVG(LENGTH(C.Text)) AS AverageCommentLength,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%thank%' OR LOWER(C.Text) LIKE '%helpful%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%wrong%' THEN 1 ELSE 0 END) AS NegativeCommentCount
    FROM Comments C
    GROUP BY C.PostId
),
PostHistoryAggregates AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 24) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteHistoryCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS HasCloseHistory,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (12, 13) THEN 1 ELSE 0 END) AS HadDeletionEvents,
        MAX(PH.CreationDate) AS LastHistoryEventDate,
        MIN(PH.CreationDate) AS FirstHistoryEventDate,
        COALESCE(
            (SELECT PH_Inner.Comment FROM PostHistory PH_Inner WHERE PH_Inner.PostId = PH.PostId AND PH_Inner.PostHistoryTypeId = 10 ORDER BY PH_Inner.CreationDate DESC LIMIT 1),
            '0'
        ) AS PrimaryCloseReasonId_Str
    FROM PostHistory PH
    GROUP BY PH.PostId
),
PostMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.OwnerUserId,
        COALESCE(P.OwnerDisplayName, 'Community') AS ActualOwnerDisplayName,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount AS DirectCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        PCS.TotalComments AS AggregatedTotalComments,
        PCS.TotalCommentScore,
        PCS.LastCommentDate,
        PCS.PositiveCommentCount,
        PCS.NegativeCommentCount,
        PHA.EditCount,
        PHA.CloseVoteHistoryCount,
        PHA.WasReopened,
        PHA.HasCloseHistory,
        PHA.PrimaryCloseReasonId_Str,
        (P.Score * 0.6) + (P.ViewCount * 0.008) + (COALESCE(P.FavoriteCount, 0) * 0.3) + (COALESCE(P.AnswerCount, 0) * 0.15) AS PostQualityScore,
        EXTRACT(EPOCH FROM (COALESCE(P.LastActivityDate, P.CreationDate) - P.CreationDate)) / 86400.0 AS DaysSinceCreationActivity,
        (COALESCE(P.AnswerCount, 0) + COALESCE(P.CommentCount, 0) + COALESCE(PCS.TotalComments,0)) / NULLIF(P.ViewCount + P.Score + 1.0, 0) AS EngagementRatio,
        LOWER(SUBSTRING(P.Tags FROM 2 FOR POSITION('><' IN P.Tags) - 2)) AS PrimaryTagFromTagsField,
        (
            SELECT COUNT(DISTINCT PH_Inner.UserId)
            FROM PostHistory PH_Inner
            INNER JOIN Users U_Inner ON PH_Inner.UserId = U_Inner.Id
            WHERE PH_Inner.PostId = P.Id
              AND PH_Inner.PostHistoryTypeId IN (4,5,6)
              AND U_Inner.Reputation > 1000
        ) AS HighReputationEditors,
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId, EXTRACT(YEAR FROM P.CreationDate) ORDER BY P.Score DESC, P.CreationDate DESC, P.FavoriteCount DESC) AS PostTypeYearlyRank,
        SUM(P.Score) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeOwnerScore,
        EXTRACT(EPOCH FROM (LEAD(P.LastActivityDate, 1, P.LastActivityDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) - P.LastActivityDate)) / 3600.0 AS TimeToNextOwnerActivityHours,
        CASE
            WHEN P.ViewCount > 5000 AND (P.LastActivityDate - P.CreationDate) < INTERVAL '14 days' AND P.Score > 100 THEN 'Very Hot'
            WHEN P.ViewCount > 1000 AND (P.LastActivityDate - P.CreationDate) < INTERVAL '30 days' AND P.Score > 50 THEN 'Hot'
            WHEN P.ViewCount > 500 AND (P.LastActivityDate - P.CreationDate) < INTERVAL '90 days' AND P.Score > 20 THEN 'Warm'
            ELSE 'Normal'
        END AS HeatTier,
        SUBSTRING(P.Title, 1, 75) || CASE WHEN LENGTH(P.Title) > 75 THEN '...' ELSE '' END AS TruncatedTitle
    FROM Posts P
    LEFT JOIN PostCommentSummary PCS ON P.Id = PCS.PostId
    LEFT JOIN PostHistoryAggregates PHA ON P.Id = PHA.PostId
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate >= DATE '2021-01-01'
      AND P.Score >= 0
),
LinkedPostsInfo AS (
    SELECT
        PL.PostId,
        COUNT(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE NULL END) AS OutgoingLinkedPostsCount,
        COUNT(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE NULL END) AS OutgoingDuplicatePostsCount,
        MAX(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS IsSourceOfDuplicate,
        (
            SELECT P_Incoming.Title
            FROM Posts P_Incoming
            INNER JOIN PostLinks PL_Incoming ON P_Incoming.Id = PL_Incoming.PostId
            WHERE PL_Incoming.RelatedPostId = PL.PostId AND PL_Incoming.LinkTypeId = 1
            ORDER BY PL_Incoming.CreationDate DESC
            LIMIT 1
        ) AS MostRecentIncomingLinkedPostTitle
    FROM PostLinks PL
    GROUP BY PL.PostId
),
QuestionTagDetails AS (
    SELECT
        PM.PostId,
        unnest(string_to_array(TRIM(BOTH '<>' FROM PM.Tags), '><')) AS ParsedTag,
        PM.PostCreationDate
    FROM PostMetrics PM
    WHERE PM.PostTypeId = 1 AND PM.Tags IS NOT NULL
),
HighlyEngagedPosts AS (
    SELECT
        PM.PostId,
        PM.TruncatedTitle AS ItemTitle,
        PM.PostCreationDate,
        PM.PostScore AS ItemScore,
        PM.ViewCount AS ItemViews,
        PM.AggregatedTotalComments AS ItemTotalComments,
        PM.EngagementRatio AS ItemEngagementRatio,
        PM.HeatTier AS ItemHeatTier,
        'Question' AS ItemType
    FROM PostMetrics PM
    WHERE PM.PostTypeId = 1
      AND PM.PostQualityScore > 500
      AND PM.EngagementRatio > 0.02
      AND COALESCE(PM.HasCloseHistory, 0) = 0
      AND PM.OwnerUserId IS NOT NULL
    UNION ALL
    SELECT
        PM.PostId,
        PM.TruncatedTitle AS ItemTitle,
        PM.PostCreationDate,
        PM.PostScore AS ItemScore,
        PM.ViewCount AS ItemViews,
        PM.AggregatedTotalComments AS ItemTotalComments,
        PM.EngagementRatio AS ItemEngagementRatio,
        PM.HeatTier AS ItemHeatTier,
        'Answer' AS ItemType
    FROM PostMetrics PM
    WHERE PM.PostTypeId = 2
      AND PM.PostScore > 100
      AND COALESCE(PM.HighReputationEditors, 0) >= 1
      AND COALESCE(PM.AggregatedTotalComments, 0) > 10
      AND COALESCE(PM.DaysSinceCreationActivity, 0) < 365
)
SELECT
    HEP.PostId,
    HEP.ItemTitle,
    HEP.ItemType,
    PT.Name AS PostTypeName,
    HEP.PostCreationDate,
    HEP.ItemScore,
    HEP.ItemViews,
    UE.ReputationTier,
    UE.UserActivityScore,
    PM.PostQualityScore,
    PM.EngagementRatio,
    PM.HeatTier,
    PM.DaysSinceCreationActivity,
    PM.TimeToNextOwnerActivityHours,
    PM.AggregatedTotalComments,
    PM.TotalCommentScore,
    PM.PositiveCommentCount,
    PM.NegativeCommentCount,
    PM.EditCount,
    PM.HighReputationEditors,
    PM.HasCloseHistory,
    COALESCE(CR.Name, 'No Specific Close Reason') AS CloseReasonCategory,
    LPI.OutgoingLinkedPostsCount,
    LPI.OutgoingDuplicatePostsCount,
    LPI.IsSourceOfDuplicate,
    LPI.MostRecentIncomingLinkedPostTitle,
    PM.PrimaryTagFromTagsField AS MainTag,
    T.TagName AS MainTagDetailsName,
    T.Count AS MainTagUsageCount,
    (PM.PostQualityScore * 0.4) + (UE.UserActivityScore * 0.2) + (PM.EngagementRatio * 200 * 0.15) + (PM.HighReputationEditors * 10 * 0.1) + (PM.TotalCommentScore * 0.05) AS OverallImpactScore,
    NTILE(5) OVER (ORDER BY (PM.PostQualityScore * 0.4) + (UE.UserActivityScore * 0.2) + (PM.EngagementRatio * 200 * 0.15) + (PM.HighReputationEditors * 10 * 0.1) + (PM.TotalCommentScore * 0.05) DESC) AS OverallImpactQuintile,
    CASE
        WHEN PM.HeatTier = 'Very Hot' AND COALESCE(PM.HighReputationEditors, 0) > 0 AND COALESCE(PM.PositiveCommentCount,0) > COALESCE(PM.NegativeCommentCount,0) THEN 'Trending & Vetted'
        WHEN PM.HeatTier = 'Hot' AND COALESCE(PM.AggregatedTotalComments,0) > 20 AND PM.EngagementRatio > 0.01 THEN 'Active Community Discussion'
        WHEN COALESCE(PM.HasCloseHistory,0) <> 0 AND COALESCE(LPI.IsSourceOfDuplicate,0) <> 0 THEN 'Problematic (Source of Duplicate)'
        WHEN COALESCE(PM.WasReopened,0) <> 0 AND COALESCE(PM.EditCount,0) > 5 THEN 'Resolved & Improved'
        WHEN COALESCE(PM.HasCloseHistory,0) <> 0 THEN 'Closed Post'
        ELSE 'Standard Activity'
    END AS PostStatusClassification,
    'Post#' || CAST(PM.PostId AS TEXT) || '-' || SUBSTRING(MD5(COALESCE(PM.Title, '')), 1, 5) AS CompositePostIdentifier,
    CASE WHEN PM.OwnerUserId IS NULL THEN 'Community Owned' ELSE 'User Owned' END AS OwnershipType
FROM HighlyEngagedPosts HEP
INNER JOIN PostMetrics PM ON HEP.PostId = PM.PostId
INNER JOIN PostTypes PT ON PM.PostTypeId = PT.Id
LEFT JOIN UserEngagement UE ON PM.OwnerUserId = UE.UserId
LEFT JOIN LinkedPostsInfo LPI ON PM.PostId = LPI.PostId
LEFT JOIN Tags T ON PM.PrimaryTagFromTagsField = LOWER(T.TagName)
LEFT JOIN CloseReasonTypes CR ON
    PM.PrimaryCloseReasonId_Str ~ '^[0-9]+$' AND CR.Id = CAST(PM.PrimaryCloseReasonId_Str AS SMALLINT)
WHERE
    PM.PostQualityScore > (
        SELECT AVG(PM_Avg.PostQualityScore)
        FROM PostMetrics PM_Avg
        WHERE PM_Avg.PostTypeId = PM.PostTypeId
          AND PM_Avg.OwnerUserId IS NOT NULL
    )
    AND PM.PostTypeYearlyRank <= 1000
    AND (
        (PM.PostTypeId = 1 AND COALESCE(PM.AggregatedTotalComments,0) > 10 AND PM.EngagementRatio > 0.01 AND COALESCE(PM.FavoriteCount,0) > 5)
        OR
        (PM.PostTypeId = 2 AND PM.PostScore > 50 AND COALESCE(PM.HighReputationEditors,0) >= 1 AND COALESCE(PM.DaysSinceCreationActivity,0) < 365)
    )
    AND UE.ReputationTier IS NOT NULL
    AND PM.TimeToNextOwnerActivityHours IS NOT NULL
ORDER BY
    OverallImpactQuintile,
    OverallImpactScore DESC,
    HEP.PostCreationDate DESC
LIMIT 2000;