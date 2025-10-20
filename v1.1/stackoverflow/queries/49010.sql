WITH UserPostStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
UserBadgeStats AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
UserPostHistoryStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(PH.Id) AS TotalPostHistoryEvents,
        COUNT(DISTINCT PH.PostId) AS UniquePostsWithHistory,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6,7,8,9) THEN PH.Id END) AS EditRollbackHistoryEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10,11,12,13) THEN PH.Id END) AS CloseReopenDeleteUndeleteEvents
    FROM Posts P
    JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserTagList AS (
    SELECT
        P2.Id AS PostId,
        TRIM(tag) AS TagName
    FROM Posts P2,
    UNNEST(string_to_array(
        CASE WHEN P2.Tags IS NULL THEN '' ELSE substring(P2.Tags, 2, GREATEST(length(P2.Tags) - 2, 0)) END
    , '><')) AS tag
    WHERE P2.Tags IS NOT NULL AND P2.Tags <> ''
),
UserTagStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT T.TagName) AS UniqueTagsContributed,
        SUM(T.Count) AS SumOfTagPopularity,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS TotalLinkedPostsCreated,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicatePostsCreated
    FROM Posts P
    JOIN UserTagList taglist ON taglist.PostId = P.Id
    JOIN Tags T ON taglist.TagName = T.TagName
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId = 1
    GROUP BY P.OwnerUserId
),
CombinedUserStats AS (
    SELECT
        UPS.UserId,
        UPS.DisplayName,
        UPS.Reputation,
        UPS.UserCreationDate,
        UPS.LastAccessDate,
        UPS.TotalPosts,
        UPS.TotalQuestions,
        UPS.TotalAnswers,
        COALESCE(UPS.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(UPS.AvgPostScore, 0.0) AS AvgPostScore,
        UPS.TotalComments,
        COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
        COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(UPHS.TotalPostHistoryEvents, 0) AS TotalPostHistoryEvents,
        COALESCE(UPHS.UniquePostsWithHistory, 0) AS UniquePostsWithHistory,
        COALESCE(UPHS.EditRollbackHistoryEvents, 0) AS EditRollbackHistoryEvents,
        COALESCE(UPHS.CloseReopenDeleteUndeleteEvents, 0) AS CloseReopenDeleteUndeleteEvents,
        COALESCE(UTS.UniqueTagsContributed, 0) AS UniqueTagsContributed,
        COALESCE(UTS.SumOfTagPopularity, 0) AS SumOfTagPopularity,
        COALESCE(UTS.TotalLinkedPostsCreated, 0) AS TotalLinkedPostsCreated,
        COALESCE(UTS.TotalDuplicatePostsCreated, 0) AS TotalDuplicatePostsCreated,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - UPS.UserCreationDate)) / (60 * 60 * 24) AS INTEGER) AS AccountAgeDays
    FROM UserPostStats UPS
    LEFT JOIN UserBadgeStats UBS ON UPS.UserId = UBS.UserId
    LEFT JOIN UserPostHistoryStats UPHS ON UPS.UserId = UPHS.UserId
    LEFT JOIN UserTagStats UTS ON UPS.UserId = UTS.UserId
    WHERE UPS.Reputation >= 5000
      AND UPS.TotalPosts >= 50
      AND COALESCE(UBS.GoldBadges, 0) >= 1
      AND COALESCE(UPHS.EditRollbackHistoryEvents, 0) >= 10
      AND COALESCE(UTS.UniqueTagsContributed, 0) >= 5
),
ScoredUsers AS (
    SELECT
        CUS.*,
        (CUS.Reputation * 0.4 +
         CUS.TotalPostScore * 0.2 +
         (CUS.GoldBadges * 100 + CUS.SilverBadges * 10 + CUS.BronzeBadges * 1) * 0.15 +
         (CUS.TotalComments + CUS.EditRollbackHistoryEvents + CUS.CloseReopenDeleteUndeleteEvents) * 0.1 +
         (CUS.UniqueTagsContributed * 5 + CUS.SumOfTagPopularity / 1000.0) * 0.1 +
         (CUS.TotalLinkedPostsCreated + CUS.TotalDuplicatePostsCreated) * 0.05
        ) AS ImpactScore
    FROM CombinedUserStats CUS
),
RankedAndTiled AS (
    SELECT
        S.*,
        RANK() OVER (ORDER BY S.Reputation DESC, S.GoldBadges DESC, S.TotalPostScore DESC, S.TotalComments DESC) AS OverallActivityRank,
        NTILE(5) OVER (ORDER BY S.ImpactScore DESC) AS UserImpactTile,
        ROW_NUMBER() OVER (PARTITION BY (S.AccountAgeDays / 365) ORDER BY S.Reputation DESC) AS RankWithinAgeGroup
    FROM ScoredUsers S
)
SELECT
    R.UserId,
    R.DisplayName,
    R.Reputation,
    R.UserCreationDate,
    R.LastAccessDate,
    R.TotalPosts,
    R.TotalQuestions,
    R.TotalAnswers,
    R.TotalPostScore,
    R.AvgPostScore,
    R.TotalComments,
    R.TotalBadges,
    R.GoldBadges,
    R.SilverBadges,
    R.BronzeBadges,
    R.TotalPostHistoryEvents,
    R.UniquePostsWithHistory,
    R.EditRollbackHistoryEvents,
    R.CloseReopenDeleteUndeleteEvents,
    R.UniqueTagsContributed,
    R.SumOfTagPopularity,
    R.TotalLinkedPostsCreated,
    R.TotalDuplicatePostsCreated,
    R.AccountAgeDays,
    R.OverallActivityRank,
    R.UserImpactTile,
    R.RankWithinAgeGroup
FROM RankedAndTiled R
WHERE R.UserImpactTile <= 2
ORDER BY R.OverallActivityRank, R.RankWithinAgeGroup
LIMIT 200;