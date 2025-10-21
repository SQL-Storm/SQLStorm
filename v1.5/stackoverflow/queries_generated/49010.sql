-- {"query": "49010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1638} 

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
        SUM(P.Score) AS TotalPostScore,
        AVG(P.Score) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
UserBadgeStats AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges
    FROM Badges AS B
    GROUP BY B.UserId
),
UserPostHistoryStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(PH.Id) AS TotalPostHistoryEvents,
        COUNT(DISTINCT PH.PostId) AS UniquePostsWithHistory,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6,7,8,9) THEN PH.Id END) AS EditRollbackHistoryEvents, -- Edits/Rollbacks to Title, Body, Tags
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10,11,12,13) THEN PH.Id END) AS CloseReopenDeleteUndeleteEvents -- Post Closed, Reopened, Deleted, Undeleted
    FROM Posts AS P
    JOIN PostHistory AS PH ON P.Id = PH.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserTagStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT T.TagName) AS UniqueTagsContributed,
        SUM(T.Count) AS SumOfTagPopularity, -- sum of 'Count' from Tags table for tags user contributed to
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS TotalLinkedPostsCreated, -- how many "linked" posts this user's posts created
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicatePostsCreated -- how many "duplicate" posts this user's posts created
    FROM Posts AS P
    JOIN LATERAL UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName ON TRUE
    JOIN Tags AS T ON TagName = T.TagName
    LEFT JOIN PostLinks AS PL ON P.Id = PL.PostId -- Links created by posts owned by this user
    WHERE P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND P.Tags != '' AND P.PostTypeId = 1 -- Only consider tags from questions for this
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
        (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - UPS.UserCreationDate)) / (60 * 60 * 24))::int AS AccountAgeDays
    FROM UserPostStats AS UPS
    LEFT JOIN UserBadgeStats AS UBS ON UPS.UserId = UBS.UserId
    LEFT JOIN UserPostHistoryStats AS UPHS ON UPS.UserId = UPHS.UserId
    LEFT JOIN UserTagStats AS UTS ON UPS.UserId = UTS.UserId
    WHERE UPS.Reputation >= 5000
      AND UPS.TotalPosts >= 50
      AND COALESCE(UBS.GoldBadges, 0) >= 1
      AND COALESCE(UPHS.EditRollbackHistoryEvents, 0) >= 10
      AND COALESCE(UTS.UniqueTagsContributed, 0) >= 5
)
SELECT
    *,
    RANK() OVER (ORDER BY Reputation DESC, GoldBadges DESC, TotalPostScore DESC, TotalComments DESC) AS OverallActivityRank,
    NTILE(5) OVER (ORDER BY (
        Reputation * 0.4 +
        TotalPostScore * 0.2 +
        (GoldBadges * 100 + SilverBadges * 10 + BronzeBadges * 1) * 0.15 +
        (TotalComments + EditRollbackHistoryEvents + CloseReopenDeleteUndeleteEvents) * 0.1 +
        (UniqueTagsContributed * 5 + SumOfTagPopularity / 1000) * 0.1 +
        (TotalLinkedPostsCreated + TotalDuplicatePostsCreated) * 0.05
    ) DESC) AS UserImpactTile,
    ROW_NUMBER() OVER (PARTITION BY (AccountAgeDays / 365) ORDER BY Reputation DESC) AS RankWithinAgeGroup
FROM CombinedUserStats
WHERE UserImpactTile <= 2 -- Only top 40% by impact
ORDER BY OverallActivityRank, RankWithinAgeGroup
LIMIT 200;
