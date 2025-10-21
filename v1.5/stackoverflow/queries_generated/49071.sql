-- {"query": "49071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1839} 
WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT Q.Id) AS TotalQuestionsAsked,
        COUNT(DISTINCT A.Id) AS TotalAnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN P.Id END) AS QuestionsWithAcceptedAnswer,
        COUNT(DISTINCT CASE WHEN A.PostTypeId = 2 AND A.Id = ParentQ.AcceptedAnswerId THEN A.Id END) AS AcceptedAnswersCount,
        SUM(P.FavoriteCount) AS TotalFavoriteCountOnPosts,
        MAX(P.CreationDate) AS LastPostActivityDate,
        MIN(P.CreationDate) AS FirstPostActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts Q ON P.Id = Q.Id AND Q.PostTypeId = 1 -- Only questions
    LEFT JOIN Posts A ON P.Id = A.Id AND A.PostTypeId = 2 -- Only answers
    LEFT JOIN Posts ParentQ ON A.ParentId = ParentQ.Id -- To check if A is an accepted answer
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
UserBadgeAndEditMetrics AS (
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        COUNT(PH.Id) AS TotalPostHistoryEntries,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 24) THEN PH.PostId END) AS DistinctPostsEdited, -- Edit Title, Edit Body, Edit Tags, Rollback Body, Rollback Tags, Suggested Edit Applied
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (1, 2, 3) THEN PH.PostId END) AS DistinctPostsCreated, -- Initial Title, Initial Body, Initial Tags
        MAX(PH.CreationDate) AS LastHistoryEntryDate
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId
    GROUP BY U.Id
),
UserTagActivity AS (
    SELECT
        U.Id AS UserId,
        TRIM(UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))) AS TagName,
        SUM(P.Score) AS UserTagScore,
        COUNT(P.Id) AS UserPostsInTag,
        SUM(P.ViewCount) AS UserTagViewCount
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.Tags IS NOT NULL AND P.Tags != ' '
    GROUP BY U.Id, TRIM(UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')))
),
TagPopularity AS (
    SELECT
        TRIM(UNNEST(string_to_array(substring(P_ALL.Tags, 2, length(P_ALL.Tags)-2), '><'))) AS TagName,
        SUM(P_ALL.Score) AS GlobalTagScore,
        COUNT(P_ALL.Id) AS GlobalTagPosts,
        SUM(P_ALL.ViewCount) AS GlobalTagViewCount
    FROM Posts P_ALL
    WHERE P_ALL.Tags IS NOT NULL AND P_ALL.Tags != ' '
    GROUP BY TRIM(UNNEST(string_to_array(substring(P_ALL.Tags, 2, length(P_ALL.Tags)-2), '><')))
),
UserOverallTagEngagement AS (
    SELECT
        UTA.UserId,
        COUNT(DISTINCT UTA.TagName) AS DistinctTagsContributed,
        SUM(UTA.UserTagScore) AS TotalUserTagContributionScore,
        SUM(UTA.UserPostsInTag) AS TotalUserPostsInTags,
        SUM(UTA.UserTagViewCount) AS TotalUserTagViewCount,
        -- Weighted engagement: User's score in a tag multiplied by the tag's global popularity metrics
        SUM(UTA.UserTagScore * TP.GlobalTagScore + UTA.UserTagViewCount * TP.GlobalTagViewCount / 100) AS WeightedTagEngagementScore
    FROM UserTagActivity UTA
    JOIN TagPopularity TP ON UTA.TagName = TP.TagName
    GROUP BY UTA.UserId
)
SELECT
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.UserCreationDate,
    UCS.TotalQuestionsAsked,
    UCS.TotalAnswersProvided,
    UCS.TotalCommentsMade,
    (UCS.TotalQuestionScore + UCS.TotalAnswerScore) AS OverallPostScore,
    UCS.AcceptedAnswersCount,
    UCS.TotalFavoriteCountOnPosts,
    UBM.TotalBadges,
    UBM.GoldBadges,
    UBM.SilverBadges,
    UBM.BronzeBadges,
    UBM.TotalPostHistoryEntries,
    UBM.DistinctPostsEdited,
    UTAE.DistinctTagsContributed,
    UTAE.TotalUserTagContributionScore,
    UTAE.WeightedTagEngagementScore,
    -- A composite score designed to highlight highly engaged users
    (
        UCS.Reputation * 0.1 +                              -- Base reputation
        (UCS.TotalQuestionScore + UCS.TotalAnswerScore) * 0.5 + -- Post score contribution
        UCS.AcceptedAnswersCount * 5 +                      -- Accepted answers are valuable
        UCS.TotalFavoriteCountOnPosts * 2 +                 -- Posts favorited by others
        UBM.GoldBadges * 100 +                              -- Gold badges are significant
        UBM.SilverBadges * 20 +                             -- Silver badges
        UBM.BronzeBadges * 5 +                              -- Bronze badges
        UBM.DistinctPostsEdited * 1 +                       -- Editing activity
        UTAE.WeightedTagEngagementScore / 10000             -- Engagement with popular tags
    ) AS CompositeEngagementScore,
    RANK() OVER (ORDER BY (
        UCS.Reputation * 0.1 +
        (UCS.TotalQuestionScore + UCS.TotalAnswerScore) * 0.5 +
        UCS.AcceptedAnswersCount * 5 +
        UCS.TotalFavoriteCountOnPosts * 2 +
        UBM.GoldBadges * 100 +
        UBM.SilverBadges * 20 +
        UBM.BronzeBadges * 5 +
        UBM.DistinctPostsEdited * 1 +
        UTAE.WeightedTagEngagementScore / 10000
    ) DESC) AS OverallEngagementRank
FROM UserContributionSummary UCS
JOIN UserBadgeAndEditMetrics UBM ON UCS.UserId = UBM.UserId
LEFT JOIN UserOverallTagEngagement UTAE ON UCS.UserId = UTAE.UserId
WHERE UCS.Reputation > 500 -- Filter for users with a minimum reputation
  AND (UCS.TotalQuestionsAsked > 0 OR UCS.TotalAnswersProvided > 0 OR UCS.TotalCommentsMade > 0) -- Ensure some form of direct contribution
  AND UCS.LastPostActivityDate IS NOT NULL -- Users must have had some recent activity
ORDER BY OverallEngagementRank ASC, UCS.Reputation DESC
LIMIT 200;