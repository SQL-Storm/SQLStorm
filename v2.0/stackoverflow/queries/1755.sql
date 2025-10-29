-- {"query": "1755.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3376}
WITH UserOverallStats AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User') AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(CAST(COALESCE(P.Score, 0) AS NUMERIC)) AS AveragePostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
        ROW_NUMBER() OVER(ORDER BY U.Reputation DESC, U.CreationDate) AS GlobalReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostTagAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName,
        LENGTH(P.Body) AS BodyLength,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
      AND P.Tags IS NOT NULL
),
PostHistoryAndClosure AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PH.PostHistoryTypeId,
        PH.UserId AS HistoryEditorId,
        COALESCE(PH.UserDisplayName, (SELECT U.DisplayName FROM Users U WHERE U.Id = PH.UserId LIMIT 1)) AS HistoryEditorDisplayName,
        PH.Comment,
        PH.Text AS HistoryText,
        COALESCE(CR.Name,
                 (SELECT CR_alt.Name FROM CloseReasonTypes CR_alt WHERE PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CR_alt.Id AS TEXT) LIMIT 1)) AS CloseReasonName,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevHistoryDate,
        (SELECT COUNT(DISTINCT PH_inner.UserId) FROM PostHistory PH_inner WHERE PH_inner.PostId = PH.PostId AND PH_inner.PostHistoryTypeId IN (4,5,6) AND PH_inner.UserId IS NOT NULL) > 1 AS HasMultipleEditors
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CR.Id AS TEXT)
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11)
),
TagMetrics AS (
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TaggedPostsCount,
        AVG(CAST(COALESCE(PostScore, 0) AS NUMERIC)) AS AverageScoreForTag,
        SUM(COALESCE(PostScore, 0)) AS TotalScoreForTag,
        SUM(COALESCE(ViewCount, 0)) AS TotalViewsForTag,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT PostId) DESC, AVG(CAST(COALESCE(PostScore, 0) AS NUMERIC)) DESC) AS TagPopularityRank
    FROM PostTagAnalysis
    WHERE PostTypeId = 1
    GROUP BY TagName
),
PostCommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScoreOnPost,
        MAX(C.CreationDate) AS LastCommentDateOnPost,
        AVG(CAST(COALESCE(C.Score, 0) AS NUMERIC)) AS AvgCommentScoreOnPost
    FROM Comments C
    GROUP BY C.PostId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgeCount,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadgeCount,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadgeCount
    FROM Badges B
    GROUP BY B.UserId
)
SELECT
    UOS.UserId,
    UOS.DisplayName AS UserDisplayName,
    UOS.Reputation,
    UOS.TotalQuestions,
    UOS.TotalAnswers,
    UOS.TotalComments,
    UOS.GoldBadges,
    UOS.GlobalReputationRank,
    PTA.PostId,
    PTA.Title AS PostTitle,
    PTA.PostCreationDate,
    PTA.PostScore,
    PTA.ViewCount,
    PTA.AnswerCount,
    PTA.CommentCount AS PostCommentCount,
    PTA.FavoriteCount,
    PTA.TagName,
    PTA.PostStatus,
    PTA.BodyLength,
    TMS.TaggedPostsCount AS TagOccurrences,
    TMS.AverageScoreForTag,
    TMS.TagPopularityRank,
    PHC_Filtered.HistoryDate AS LatestHistoryDate,
    PHC_Filtered.PostHistoryTypeId AS LatestHistoryType,
    PHC_Filtered.HistoryEditorDisplayName AS LatestEditor,
    COALESCE(PHC_Filtered.CloseReasonName, 'N/A') AS PostClosureReason,
    EXTRACT(EPOCH FROM (PTA.PostCreationDate - PHC_Filtered.PrevHistoryDate)) / 3600 AS HoursSincePrevHistory,
    PHC_Filtered.HasMultipleEditors,
    PCS.TotalCommentsOnPost,
    PCS.TotalCommentScoreOnPost,
    PCS.LastCommentDateOnPost,
    UBS.TotalBadges,
    UBS.GoldBadgeCount,
    (
        SELECT AVG(CAST(RelatedPost.Score AS NUMERIC))
        FROM PostLinks PL
        JOIN Posts RelatedPost ON PL.RelatedPostId = RelatedPost.Id
        WHERE PL.PostId = PTA.PostId AND PL.LinkTypeId = 1 AND RelatedPost.PostTypeId = 1
    ) AS AvgLinkedQuestionScore,
    ROW_NUMBER() OVER(PARTITION BY PTA.TagName ORDER BY PTA.PostScore DESC, PTA.ViewCount DESC) AS PostRankInTag,
    LEFT(COALESCE(PTA.Title, 'No Title') || ' - ' || SUBSTRING(P_Body.Body, 1, 50), 100) AS PostSnippet,
    (UOS.TotalPosts * 0.5 + UOS.TotalComments * 0.3 + UOS.Reputation * 0.01 + UOS.GoldBadges * 5.0) AS UserEngagementScore
FROM UserOverallStats UOS
JOIN PostTagAnalysis PTA ON UOS.UserId = PTA.OwnerUserId
JOIN TagMetrics TMS ON PTA.TagName = TMS.TagName
LEFT JOIN PostCommentSummary PCS ON PTA.PostId = PCS.PostId
LEFT JOIN UserBadgeSummary UBS ON UOS.UserId = UBS.UserId
LEFT JOIN Posts P_Body ON PTA.PostId = P_Body.Id
LEFT JOIN LATERAL (
    SELECT *
    FROM PostHistoryAndClosure PHC_inner
    WHERE PHC_inner.PostId = PTA.PostId
    ORDER BY PHC_inner.HistoryDate DESC
    LIMIT 1
) AS PHC_Filtered ON TRUE
WHERE
    UOS.Reputation > 1000
    AND UOS.TotalQuestions > 0
    AND PTA.PostCreationDate >= DATE '2022-01-01'
    AND PTA.PostScore > COALESCE((SELECT AVG(CAST(p_avg.Score AS NUMERIC)) FROM Posts p_avg WHERE p_avg.OwnerUserId = UOS.UserId AND p_avg.PostTypeId = PTA.PostTypeId), 0)
    AND PTA.PostStatus = 'Open'
    AND PTA.TagName LIKE 'sql%'
    AND PTA.BodyLength > 100
    AND (PCS.TotalCommentsOnPost IS NULL OR PCS.TotalCommentsOnPost < 10)
    AND (UOS.TotalPosts * 0.5 + UOS.TotalComments * 0.3 + UOS.Reputation * 0.01 + UOS.GoldBadges * 5.0) > 100.0
GROUP BY
    UOS.UserId, UOS.DisplayName, UOS.Reputation, UOS.TotalPosts, UOS.TotalQuestions, UOS.TotalAnswers, UOS.TotalComments, UOS.GoldBadges, UOS.GlobalReputationRank,
    PTA.PostId, PTA.Title, PTA.PostCreationDate, PTA.PostScore, PTA.ViewCount, PTA.AnswerCount, PTA.CommentCount, PTA.FavoriteCount,
    PTA.TagName, PTA.PostStatus, PTA.BodyLength, TMS.TaggedPostsCount, TMS.AverageScoreForTag, TMS.TagPopularityRank,
    PHC_Filtered.HistoryDate, PHC_Filtered.PostHistoryTypeId, PHC_Filtered.HistoryEditorDisplayName, PHC_Filtered.CloseReasonName, PHC_Filtered.PrevHistoryDate,
    PHC_Filtered.HasMultipleEditors, PCS.TotalCommentsOnPost, PCS.TotalCommentScoreOnPost, PCS.LastCommentDateOnPost,
    UBS.TotalBadges, UBS.GoldBadgeCount, P_Body.Body
HAVING
    COUNT(DISTINCT PTA.PostId) > 1
    AND MAX(COALESCE(PTA.FavoriteCount, 0)) > 0
UNION ALL
SELECT
    U.Id AS UserId,
    COALESCE(U.DisplayName, 'Anonymous User') AS UserDisplayName,
    U.Reputation,
    COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
    COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
    COUNT(C.Id) AS TotalComments,
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
    CAST(NULL AS BIGINT) AS GlobalReputationRank,
    P.Id AS PostId,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount,
    P.AnswerCount,
    P.CommentCount AS PostCommentCount,
    P.FavoriteCount,
    'No_Tags_Found' AS TagName,
    'Open_or_Unknown' AS PostStatus,
    LENGTH(P.Body) AS BodyLength,
    0 AS TagOccurrences,
    0.0 AS AverageScoreForTag,
    0 AS TagPopularityRank,
    CAST(NULL AS TIMESTAMP) AS LatestHistoryDate,
    CAST(NULL AS SMALLINT) AS LatestHistoryType,
    CAST(NULL AS VARCHAR(40)) AS LatestEditor,
    'N/A - No Tags' AS PostClosureReason,
    CAST(NULL AS NUMERIC) AS HoursSincePrevHistory,
    FALSE AS HasMultipleEditors,
    CAST(NULL AS BIGINT) AS TotalCommentsOnPost,
    CAST(NULL AS BIGINT) AS TotalCommentScoreOnPost,
    CAST(NULL AS TIMESTAMP) AS LastCommentDateOnPost,
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id) AS TotalBadges,
    (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadgeCount,
    CAST(NULL AS NUMERIC) AS AvgLinkedQuestionScore,
    CAST(NULL AS BIGINT) AS PostRankInTag,
    LEFT(COALESCE(P.Title, 'No Title') || ' - ' || SUBSTRING(P.Body, 1, 50), 100) AS PostSnippet,
    (U.UpVotes * 0.8 + U.DownVotes * -0.2 + U.Views * 0.05) AS UserEngagementScore
FROM Users U
JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Comments C ON U.Id = C.UserId
WHERE
    P.Tags IS NULL
    AND P.PostTypeId = 1
    AND P.Score > 500
    AND P.CreationDate < DATE '2020-01-01'
GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.Views, P.Id, P.Title, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Body
ORDER BY UserEngagementScore DESC, PostScore DESC, PostCreationDate DESC
LIMIT 10000;