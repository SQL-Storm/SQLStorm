WITH UserBaseStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostDetailsExpanded AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount AS QuestionAnswerCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        CASE WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
             THEN string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')
             ELSE CAST(ARRAY[] AS VARCHAR[])
        END AS TagArray,
        COUNT(DISTINCT C.Id) AS PostCommentCount,
        COUNT(DISTINCT PH_Edit.Id) AS EditCount,
        COUNT(DISTINCT PH_Close.Id) AS CloseCount,
        COUNT(DISTINCT PH_Reopen.Id) AS ReopenCount,
        MAX(CASE WHEN P.PostTypeId = 2 AND ParentQ.AcceptedAnswerId = P.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    LEFT JOIN Posts ParentQ ON P.PostTypeId = 2 AND P.ParentId = ParentQ.Id AND ParentQ.PostTypeId = 1
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.CreationDate, P.LastActivityDate, P.Tags
),
UserContentSummary AS (
    SELECT
        PDE.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN PDE.PostTypeId = 1 THEN PDE.PostId END) AS QuestionsPosted,
        COUNT(DISTINCT CASE WHEN PDE.PostTypeId = 2 THEN PDE.PostId END) AS AnswersPosted,
        SUM(PDE.PostScore) AS TotalPostsScore,
        SUM(CASE WHEN PDE.PostTypeId = 1 THEN PDE.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(PDE.FavoriteCount) AS TotalPostsFavorites,
        SUM(PDE.QuestionAnswerCount) AS TotalAnswersReceivedOnQuestions,
        SUM(PDE.PostCommentCount) AS TotalCommentsOnOwnPosts,
        SUM(PDE.EditCount) AS TotalEditsToOwnPosts,
        SUM(PDE.CloseCount) AS TotalPostsClosed,
        SUM(PDE.ReopenCount) AS TotalPostsReopened,
        SUM(PDE.IsAcceptedAnswer) AS AcceptedAnswersCount
    FROM PostDetailsExpanded PDE
    GROUP BY PDE.OwnerUserId
),
TagAverageScores AS (
    SELECT
        TagName,
        AVG(PostScore) AS AvgScore,
        COUNT(PostId) AS PostCountWithTag
    FROM (
        SELECT PDE.PostId, PDE.PostScore, UNNEST(PDE.TagArray) AS TagName
        FROM PostDetailsExpanded PDE
        WHERE COALESCE(ARRAY_LENGTH(PDE.TagArray, 1), 0) > 0
    ) t
    GROUP BY TagName
),
UserTagContribution AS (
    SELECT
        ut.OwnerUserId AS UserId,
        AVG(TAS.AvgScore) AS AvgUserTagPerformanceScore,
        COUNT(DISTINCT ut.TagName) AS UniqueTagsContributed
    FROM (
        SELECT PDE.OwnerUserId, UNNEST(PDE.TagArray) AS TagName
        FROM PostDetailsExpanded PDE
        WHERE COALESCE(ARRAY_LENGTH(PDE.TagArray, 1), 0) > 0
    ) ut
    JOIN TagAverageScores TAS ON ut.TagName = TAS.TagName
    GROUP BY ut.OwnerUserId
)
SELECT
    UBS.UserId,
    UBS.DisplayName,
    UBS.Reputation,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    COALESCE(UCS.QuestionsPosted, 0) AS QuestionsPosted,
    COALESCE(UCS.AnswersPosted, 0) AS AnswersPosted,
    COALESCE(UCS.TotalPostsScore, 0) AS TotalPostsScore,
    COALESCE(UCS.TotalQuestionViews, 0) AS TotalQuestionViews,
    COALESCE(UCS.TotalPostsFavorites, 0) AS TotalPostsFavorites,
    COALESCE(UCS.AcceptedAnswersCount, 0) AS AcceptedAnswersCount,
    COALESCE(UTC.AvgUserTagPerformanceScore, 0.0) AS AvgUserTagPerformanceScore,
    COALESCE(UTC.UniqueTagsContributed, 0) AS UniqueTagsContributed,
    (
        UBS.Reputation * 0.05 +
        UBS.GoldBadges * 100 +
        UBS.SilverBadges * 50 +
        UBS.BronzeBadges * 10 +
        COALESCE(UCS.QuestionsPosted, 0) * 3 +
        COALESCE(UCS.AnswersPosted, 0) * 6 +
        COALESCE(UCS.TotalPostsScore, 0) * 0.2 +
        COALESCE(UCS.TotalQuestionViews, 0) * 0.0005 +
        COALESCE(UCS.TotalPostsFavorites, 0) * 1.5 +
        COALESCE(UCS.AcceptedAnswersCount, 0) * 10 +
        COALESCE(UTC.AvgUserTagPerformanceScore, 0.0) * 0.1 +
        COALESCE(UTC.UniqueTagsContributed, 0) * 2 -
        COALESCE(UCS.TotalPostsClosed, 0) * 5
    ) AS UserImpactScore,
    RANK() OVER (ORDER BY (
        UBS.Reputation * 0.05 +
        UBS.GoldBadges * 100 +
        UBS.SilverBadges * 50 +
        UBS.BronzeBadges * 10 +
        COALESCE(UCS.QuestionsPosted, 0) * 3 +
        COALESCE(UCS.AnswersPosted, 0) * 6 +
        COALESCE(UCS.TotalPostsScore, 0) * 0.2 +
        COALESCE(UCS.TotalQuestionViews, 0) * 0.0005 +
        COALESCE(UCS.TotalPostsFavorites, 0) * 1.5 +
        COALESCE(UCS.AcceptedAnswersCount, 0) * 10 +
        COALESCE(UTC.AvgUserTagPerformanceScore, 0.0) * 0.1 +
        COALESCE(UTC.UniqueTagsContributed, 0) * 2 -
        COALESCE(UCS.TotalPostsClosed, 0) * 5
    ) DESC) AS OverallImpactRank
FROM UserBaseStats UBS
LEFT JOIN UserContentSummary UCS ON UBS.UserId = UCS.UserId
LEFT JOIN UserTagContribution UTC ON UBS.UserId = UTC.UserId
WHERE UBS.Reputation > 500
  AND (COALESCE(UCS.QuestionsPosted, 0) > 0 OR COALESCE(UCS.AnswersPosted, 0) > 0)
  AND UBS.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
ORDER BY UserImpactScore DESC, UBS.Reputation DESC
LIMIT 1000;