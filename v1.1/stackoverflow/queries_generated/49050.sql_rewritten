-- {"query": "49050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2067} 
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersProvided,
        SUM(P.Score) AS TotalPostScoreReceived,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(P.FavoriteCount) AS TotalFavoriteCountReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMadeByUser
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
AcceptedAnswersSummary AS (
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(A.Id) AS AcceptedAnswersCount,
        SUM(A.Score) AS AcceptedAnswersScore
    FROM Posts A
    INNER JOIN Posts Q ON A.Id = Q.AcceptedAnswerId
    WHERE A.PostTypeId = 2 AND Q.PostTypeId = 1
    GROUP BY A.OwnerUserId
),
PostHistoryEditsSummary AS (
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalPostHistoryEntries,
        COUNT(DISTINCT PH.PostId) AS UniquePostsEdited,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6,7,8,9,14,15) THEN 1 ELSE 0 END) AS TotalRelevantEdits
    FROM PostHistory PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
BadgesSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadgesEarned,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
VotesReceivedOnPostsSummary AS (
    SELECT
        P.OwnerUserId AS UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 2 AND V.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days' THEN 1 ELSE 0 END) AS RecentUpvotesReceivedOnPosts,
        SUM(CASE WHEN V.VoteTypeId = 3 AND V.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days' THEN 1 ELSE 0 END) AS RecentDownvotesReceivedOnPosts
    FROM Posts P
    INNER JOIN Votes V ON P.Id = V.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserTagEngagement AS (
    SELECT
        P.OwnerUserId AS UserId,
        TagData.TagName,
        COUNT(P.Id) AS PostsCountInTag,
        SUM(P.Score) AS ScoreInTag,
        ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId ORDER BY COUNT(P.Id) DESC, SUM(P.Score) DESC) AS TagRankByPosts,
        RANK() OVER(PARTITION BY P.OwnerUserId ORDER BY SUM(P.Score) DESC, COUNT(P.Id) DESC) AS TagRankByScore
    FROM Posts P
    JOIN LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS TagName) AS TagData ON P.Tags IS NOT NULL AND P.Tags != ''
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId, TagData.TagName
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.LastAccessDate,
    UAS.TotalPosts,
    UAS.TotalQuestionsAsked,
    UAS.TotalAnswersProvided,
    COALESCE(AAS.AcceptedAnswersCount, 0) AS AcceptedAnswersProvided,
    UAS.TotalPostScoreReceived,
    COALESCE(VRS.TotalUpvotesReceivedOnPosts, 0) AS TotalUpvotesReceived,
    COALESCE(VRS.TotalDownvotesReceivedOnPosts, 0) AS TotalDownvotesReceived,
    UAS.TotalQuestionViews,
    UAS.TotalFavoriteCountReceived,
    UAS.TotalCommentsMadeByUser,
    COALESCE(PHES.TotalRelevantEdits, 0) AS TotalPostEditsCount,
    COALESCE(BS.TotalBadgesEarned, 0) AS TotalBadgesEarned,
    COALESCE(BS.GoldBadges, 0) AS GoldBadges,
    COALESCE(BS.SilverBadges, 0) AS SilverBadges,
    COALESCE(BS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(VRS.RecentUpvotesReceivedOnPosts, 0) AS RecentUpvotesReceived,
    COALESCE(VRS.RecentDownvotesReceivedOnPosts, 0) AS RecentDownvotesReceived,
    MAX(CASE WHEN UTE.TagRankByPosts = 1 THEN UTE.TagName ELSE NULL END) AS TopTag1_ByPosts,
    MAX(CASE WHEN UTE.TagRankByPosts = 1 THEN UTE.PostsCountInTag ELSE NULL END) AS TopTag1_PostsCount,
    MAX(CASE WHEN UTE.TagRankByPosts = 2 THEN UTE.TagName ELSE NULL END) AS TopTag2_ByPosts,
    MAX(CASE WHEN UTE.TagRankByPosts = 2 THEN UTE.PostsCountInTag ELSE NULL END) AS TopTag2_PostsCount,
    MAX(CASE WHEN UTE.TagRankByPosts = 3 THEN UTE.TagName ELSE NULL END) AS TopTag3_ByPosts,
    MAX(CASE WHEN UTE.TagRankByPosts = 3 THEN UTE.PostsCountInTag ELSE NULL END) AS TopTag3_PostsCount,
    RANK() OVER (ORDER BY
        UAS.Reputation DESC,
        UAS.TotalPostScoreReceived DESC,
        COALESCE(AAS.AcceptedAnswersCount, 0) DESC,
        (COALESCE(VRS.RecentUpvotesReceivedOnPosts, 0) * 1.0 / (COALESCE(VRS.RecentUpvotesReceivedOnPosts, 0) + COALESCE(VRS.RecentDownvotesReceivedOnPosts, 0) + 1.0)) DESC,
        (UAS.TotalQuestionsAsked + UAS.TotalAnswersProvided) DESC
    ) AS OverallUserRank
FROM UserActivitySummary UAS
LEFT JOIN AcceptedAnswersSummary AAS ON UAS.UserId = AAS.UserId
LEFT JOIN PostHistoryEditsSummary PHES ON UAS.UserId = PHES.UserId
LEFT JOIN BadgesSummary BS ON UAS.UserId = BS.UserId
LEFT JOIN VotesReceivedOnPostsSummary VRS ON UAS.UserId = VRS.UserId
LEFT JOIN UserTagEngagement UTE ON UAS.UserId = UTE.UserId AND UTE.TagRankByPosts <= 3
WHERE UAS.TotalPosts > 100
AND UAS.Reputation > 1000
AND UAS.LastAccessDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserCreationDate, UAS.LastAccessDate,
    UAS.TotalPosts, UAS.TotalQuestionsAsked, UAS.TotalAnswersProvided, AAS.AcceptedAnswersCount,
    UAS.TotalPostScoreReceived, VRS.TotalUpvotesReceivedOnPosts, VRS.TotalDownvotesReceivedOnPosts,
    UAS.TotalQuestionViews, UAS.TotalFavoriteCountReceived, UAS.TotalCommentsMadeByUser,
    PHES.TotalRelevantEdits, BS.TotalBadgesEarned, BS.GoldBadges, BS.SilverBadges, BS.BronzeBadges,
    VRS.RecentUpvotesReceivedOnPosts, VRS.RecentDownvotesReceivedOnPosts
HAVING COUNT(DISTINCT UTE.TagName) >= 1
ORDER BY OverallUserRank ASC, UAS.Reputation DESC
LIMIT 1000;