-- {"query": "49065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1848} 

WITH TargetTags AS (
    SELECT 'javascript' AS TagName UNION ALL
    SELECT 'python' UNION ALL
    SELECT 'sql' UNION ALL
    SELECT 'performance' UNION ALL
    SELECT 'database' UNION ALL
    SELECT 'c#' UNION ALL
    SELECT 'java'
),
FilteredPosts AS (
    SELECT
        P.Id,
        P.PostTypeId,
        P.OwnerUserId,
        P.ParentId,
        P.Score,
        P.CreationDate,
        P.AcceptedAnswerId,
        P.Title,
        P.Tags
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Questions (1) and Answers (2)
      AND P.CreationDate >= '2020-01-01' -- Focus on recent activity
      AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- Ensure Tags column is not empty or malformed
      AND EXISTS (
          SELECT 1
          FROM TargetTags TT
          WHERE '<' || TT.TagName || '>' = ANY(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))
      )
),
UserContributionStats AS (
    SELECT
        FP.OwnerUserId AS UserId,
        COUNT(FP.Id) AS TotalPostsContributed,
        SUM(FP.Score) AS TotalContributionScore,
        COUNT(CASE WHEN FP.PostTypeId = 1 THEN 1 END) AS QuestionsAsked,
        COUNT(CASE WHEN FP.PostTypeId = 2 THEN 1 END) AS AnswersProvided,
        COUNT(DISTINCT CASE WHEN FP.PostTypeId = 1 AND FP.AcceptedAnswerId IS NOT NULL THEN FP.Id END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN FP.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts Q WHERE Q.Id = FP.ParentId AND Q.AcceptedAnswerId = FP.Id) THEN 1 ELSE 0 END) AS AcceptedAnswersGiven
    FROM FilteredPosts FP
    WHERE FP.OwnerUserId IS NOT NULL
    GROUP BY FP.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges
    FROM Badges B
    GROUP BY B.UserId
),
UserActivityHistory AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT PH.PostId) AS UniquePostsAffected,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount, -- Title, Body, Tags edits
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14, 19) THEN 1 END) AS NotableModerationRelatedActions -- Post Closed, Deleted, Locked, Protected
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
      AND PH.CreationDate >= '2020-01-01'
    GROUP BY PH.UserId
),
UserEngagementMetrics AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(V.Id) AS TotalVotesReceivedOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceivedOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceivedOnPosts
    FROM Votes V
    JOIN Posts P ON V.PostId = P.Id
    WHERE P.OwnerUserId IS NOT NULL
      AND V.CreationDate >= '2020-01-01'
      AND V.VoteTypeId IN (2, 5) -- UpMod (2), Favorite (5)
    GROUP BY P.OwnerUserId
)
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.Views AS UserProfileViews,
    U.UpVotes AS UserGivenUpvotes,
    U.DownVotes AS UserGivenDownvotes,
    U.CreationDate AS UserCreationDate,
    COALESCE(UCS.TotalPostsContributed, 0) AS TotalPostsContributed,
    COALESCE(UCS.TotalContributionScore, 0) AS TotalContributionScore,
    COALESCE(UCS.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(UCS.AnswersProvided, 0) AS AnswersProvided,
    COALESCE(UCS.QuestionsWithAcceptedAnswer, 0) AS QuestionsWithAcceptedAnswer,
    COALESCE(UCS.AcceptedAnswersGiven, 0) AS AcceptedAnswersGiven,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UAH.TotalHistoryEvents, 0) AS TotalHistoryEvents,
    COALESCE(UAH.UniquePostsAffected, 0) AS UniquePostsAffected,
    COALESCE(UAH.EditCount, 0) AS EditCount,
    COALESCE(UAH.NotableModerationRelatedActions, 0) AS NotableModerationRelatedActions,
    COALESCE(UEM.UpvotesReceivedOnPosts, 0) AS UpvotesReceivedOnPosts,
    COALESCE(UEM.FavoritesReceivedOnPosts, 0) AS FavoritesReceivedOnPosts,
    -- Calculate a composite influence score
    (
        U.Reputation * 0.5 +
        COALESCE(UCS.TotalContributionScore, 0) * 0.2 +
        COALESCE(UCS.AcceptedAnswersGiven, 0) * 5 +
        COALESCE(UBS.GoldBadges, 0) * 10 +
        COALESCE(UBS.SilverBadges, 0) * 5 +
        COALESCE(UEM.UpvotesReceivedOnPosts, 0) * 0.1 +
        COALESCE(UAH.EditCount, 0) * 0.05
    ) AS InfluenceScore,
    RANK() OVER (ORDER BY (
        U.Reputation * 0.5 +
        COALESCE(UCS.TotalContributionScore, 0) * 0.2 +
        COALESCE(UCS.AcceptedAnswersGiven, 0) * 5 +
        COALESCE(UBS.GoldBadges, 0) * 10 +
        COALESCE(UBS.SilverBadges, 0) * 5 +
        COALESCE(UEM.UpvotesReceivedOnPosts, 0) * 0.1 +
        COALESCE(UAH.EditCount, 0) * 0.05
    ) DESC) AS OverallRank
FROM Users U
LEFT JOIN UserContributionStats UCS ON U.Id = UCS.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN UserActivityHistory UAH ON U.Id = UAH.UserId
LEFT JOIN UserEngagementMetrics UEM ON U.Id = UEM.UserId
WHERE U.Reputation > 1000 -- Filter for reasonably established users
  AND (
        COALESCE(UCS.TotalPostsContributed, 0) > 0 OR
        COALESCE(UBS.TotalBadges, 0) > 0 OR
        COALESCE(UAH.TotalHistoryEvents, 0) > 0 OR
        COALESCE(UEM.UpvotesReceivedOnPosts, 0) > 0
      ) -- Ensure they have some activity in the filtered context
ORDER BY InfluenceScore DESC, U.Reputation DESC
LIMIT 100;
