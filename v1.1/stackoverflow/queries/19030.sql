WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score END), 0) AS AvgScorePerOwnedPost,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS ReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostContentAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.AcceptedAnswerId,
        P.ParentId,
        P.LastActivityDate,
        P.ClosedDate,
        SUBSTRING(REPLACE(REPLACE(COALESCE(P.Body, ''), CHR(10), ' '), CHR(9), ' '), 1, 200) AS BodyExcerpt,
        (P.Tags ILIKE '%<sql>%' OR P.Tags ILIKE '%<database>%' OR P.Body ILIKE '%database management%') AS IsDbRelated,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - P.CreationDate)) / (60 * 60 * 24) AS PostAgeDays,
        AVG(P.Score) OVER (PARTITION BY P.PostTypeId, EXTRACT(YEAR FROM P.CreationDate), EXTRACT(MONTH FROM P.CreationDate)) AS AvgMonthlyPostTypeScore,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC, P.CreationDate DESC) AS ViewCountRankByPostType
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.PostTypeId IN (1, 2)
),
TagUsageStats AS (
    SELECT
        PCA.PostId,
        PCA.OwnerUserId,
        (
            SELECT COUNT(DISTINCT T.Id)
            FROM Tags T
            WHERE PCA.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
        ) AS MatchedUniqueTagCount,
        EXISTS (
            SELECT 1
            FROM Badges B
            JOIN Tags T ON B.Name = T.TagName
            WHERE PCA.Tags LIKE '%' || '<' || T.TagName || '>' || '%' AND B.Class = 1
        ) AS HasGoldTagBadge
    FROM PostContentAnalysis PCA
    WHERE PCA.Tags IS NOT NULL
),
PostHistoryAnalysis AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS HasBodyEditHistory,
        (
            SELECT MAX(U_INNER.Reputation)
            FROM Users U_INNER
            JOIN PostHistory PH2 ON PH2.UserId = U_INNER.Id
            WHERE PH2.PostId = PH.PostId
        ) AS EditorMaxReputation,
        COALESCE(MAX(CRT.Name) FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL), 'Not Closed Or No Reason') AS LatestCloseReason
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRT ON PH.Comment = CAST(CRT.Id AS varchar) AND PH.PostHistoryTypeId = 10
    GROUP BY PH.PostId
),
UserBadgeMetrics AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(COUNT(B.Id)) OVER (PARTITION BY EXTRACT(YEAR FROM U.CreationDate)) AS AvgBadgesPerCreationYear
    FROM Badges B
    JOIN Users U ON B.UserId = U.Id
    GROUP BY B.UserId, U.CreationDate
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.ReputationRank,
    UAS.UserCreationDate,
    UAS.TotalPostsCreated,
    UAS.TotalCommentsMade,
    UAS.AvgScorePerOwnedPost,
    UBM.GoldBadges,
    UBM.SilverBadges,
    UBM.BronzeBadges,
    UBM.AvgBadgesPerCreationYear,
    PCA.PostId,
    PCA.PostTypeName,
    PCA.Title AS PostTitle,
    PCA.Score AS PostScore,
    PCA.ViewCount AS PostViewCount,
    PCA.PostAgeDays,
    PCA.IsDbRelated,
    PCA.AvgMonthlyPostTypeScore,
    PCA.ViewCountRankByPostType,
    TUS.MatchedUniqueTagCount,
    TUS.HasGoldTagBadge,
    PHA.TotalHistoryEntries AS PostEditHistoryCount,
    PHA.HasBodyEditHistory,
    PHA.EditorMaxReputation,
    PHA.LatestCloseReason,
    (PCA.ViewCount * 0.1 + PCA.Score * 0.5 + COALESCE(P.CommentCount, 0) * 0.8 + COALESCE(P.FavoriteCount, 0) * 1.2) AS EngagementScore,
    (CASE WHEN PCA.PostTypeId = 1 AND PCA.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END) AS HasAcceptedAnswer,
    UAS.DisplayName || ' from ' || COALESCE(SUBSTRING(U.Location, 1, 20), 'Unknown') AS UserLocationSummary,
    (
        SELECT COUNT(V.Id)
        FROM Votes V
        JOIN Users VU ON V.UserId = VU.Id
        WHERE V.PostId = PCA.PostId AND V.VoteTypeId = 2 AND VU.Reputation > 1000
    ) AS HighReputationUpvotes,
    NULL AS HighlyRatedPostIds
FROM UserActivitySummary UAS
JOIN Users U ON UAS.UserId = U.Id
LEFT JOIN UserBadgeMetrics UBM ON UAS.UserId = UBM.UserId
INNER JOIN PostContentAnalysis PCA ON UAS.UserId = PCA.OwnerUserId
LEFT JOIN TagUsageStats TUS ON PCA.PostId = TUS.PostId
LEFT JOIN PostHistoryAnalysis PHA ON PCA.PostId = PHA.PostId
LEFT JOIN Posts P ON PCA.PostId = P.Id
WHERE
    UAS.Reputation > 10000
    AND PCA.PostAgeDays < 365
    AND (
        PCA.Score > 50
        OR PCA.ViewCount > 5000
    )
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.ReputationRank,
    UAS.UserCreationDate,
    UAS.TotalPostsCreated,
    UAS.TotalCommentsMade,
    UAS.AvgScorePerOwnedPost,
    UBM.GoldBadges,
    UBM.SilverBadges,
    UBM.BronzeBadges,
    UBM.AvgBadgesPerCreationYear,
    PCA.PostId,
    PCA.PostTypeName,
    PCA.Title,
    PCA.Score,
    PCA.ViewCount,
    PCA.PostAgeDays,
    PCA.IsDbRelated,
    PCA.AvgMonthlyPostTypeScore,
    PCA.ViewCountRankByPostType,
    TUS.MatchedUniqueTagCount,
    TUS.HasGoldTagBadge,
    PHA.TotalHistoryEntries,
    PHA.HasBodyEditHistory,
    PHA.EditorMaxReputation,
    PHA.LatestCloseReason,
    P.CommentCount,
    P.FavoriteCount,
    PCA.PostTypeId,
    PCA.AcceptedAnswerId,
    U.Location,
    P.Id,
    P.CreationDate
ORDER BY
    UAS.Reputation DESC,
    EngagementScore DESC,
    P.CreationDate DESC
LIMIT 1000;