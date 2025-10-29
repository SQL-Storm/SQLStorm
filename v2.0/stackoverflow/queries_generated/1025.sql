-- {"query": "1025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2453} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.Views AS UserProfileViews,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersGiven,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(B.Id) AS TotalBadgesAwarded,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views
),
QuestionContext AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.ViewCount AS QuestionViewCount,
        Q.CreationDate AS QuestionCreationDate,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Tags AS QuestionTagsString,
        COALESCE(Q.AnswerCount, 0) AS DirectAnswerCount,
        SUM(V.BountyAmount) FILTER (WHERE V.VoteTypeId = 8) AS TotalBountyAmount,
        MAX(CASE WHEN Q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS WasEverClosed,
        STRING_AGG(DISTINCT T.TagName, ' | ') FILTER (WHERE T.TagName IS NOT NULL) AS ConsolidatedTags,
        AVG(CASE WHEN PT.TagName IS NOT NULL THEN PT.Count ELSE 0 END) AS AvgTagPopularityScore
    FROM Posts AS Q
    LEFT JOIN Votes AS V ON Q.Id = V.PostId AND V.VoteTypeId = 8 -- BountyStart
    LEFT JOIN LATERAL (SELECT unnest(string_to_array(substring(Q.Tags, 2, length(Q.Tags)-2), '><')) AS TagName) AS T ON TRUE
    LEFT JOIN Tags AS PT ON T.TagName = PT.TagName
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.Title, Q.ViewCount, Q.CreationDate, Q.OwnerUserId, Q.Tags, Q.AnswerCount, Q.ClosedDate
),
AnswerDetails AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId AS AnswerOwnerId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        A.LastEditDate AS AnswerLastEditDate,
        LENGTH(A.Body) AS AnswerBodyLength,
        Q.ViewCount AS ParentQuestionViewCount,
        (CASE WHEN Q.AcceptedAnswerId = A.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerScoreRankForQuestion,
        LAG(A.Score, 1, 0) OVER (PARTITION BY A.ParentId ORDER BY A.CreationDate ASC) AS PrevAnswerScoreByDate,
        COUNT(DISTINCT C.Id) AS AnswerCommentCount,
        SUM(V.BountyAmount) FILTER (WHERE V.VoteTypeId = 9) AS BountyReceivedOnAnswer
    FROM Posts AS A
    INNER JOIN Posts AS Q ON A.ParentId = Q.Id
    LEFT JOIN Comments AS C ON A.Id = C.PostId
    LEFT JOIN Votes AS V ON A.Id = V.PostId AND V.VoteTypeId = 9 -- BountyClose
    WHERE A.PostTypeId = 2 AND Q.PostTypeId = 1
    GROUP BY A.Id, A.ParentId, A.OwnerUserId, A.Score, A.CreationDate, A.LastEditDate, A.Body, Q.ViewCount, Q.AcceptedAnswerId
),
PostHistoryTimeline AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS HasBodyEdit,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE NULL END) AS TotalEditEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10,11) THEN 1 ELSE NULL END) AS CloseReopenCycleCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN COALESCE(CR.Name, 'Unknown') ELSE NULL END) AS LastKnownCloseReason,
        MAX(CASE WHEN PH.PostHistoryTypeId = 16 THEN 'Yes' ELSE 'No' END) AS CommunityOwnedEver,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId = 10) AS LastClosedDate,
        STRING_AGG(DISTINCT PH.Text, ' || ') FILTER (WHERE PH.PostHistoryTypeId IN (35, 36) AND PH.Text IS NOT NULL) AS MigrationDetailsConcat
    FROM PostHistory AS PH
    LEFT JOIN CloseReasonTypes AS CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CR.Id::varchar(50)
    GROUP BY PH.PostId
),
UserPostActivitySummary AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalQuestionsAsked,
        UE.TotalAnswersGiven,
        UE.GoldBadges,
        UE.SilverBadges,
        UE.BronzeBadges,
        COALESCE(CAST(UE.TotalAnswerScore AS NUMERIC) / NULLIF(UE.TotalAnswersGiven, 0), 0) AS AvgAnswerScore,
        COALESCE(CAST(SUM(AD.IsAcceptedAnswer) AS NUMERIC) / NULLIF(COUNT(AD.AnswerId), 0), 0) AS AcceptedAnswerRatio,
        COUNT(DISTINCT AD.QuestionId) AS UniqueQuestionsAnswered,
        SUM(AD.AnswerCommentCount) AS TotalCommentsOnAnswers,
        MAX(PCT.AvgTagPopularityScore) AS MaxTagPopForAnsweredQuestions,
        AVG(AD.ParentQuestionViewCount) FILTER (WHERE AD.ParentQuestionViewCount > 0) AS AvgViewCountOfAnsweredQuestions,
        SUM(PH.TotalEditEvents) AS TotalPostEditEventsAcrossPosts,
        SUM(PH.CloseReopenCycleCount) AS TotalCloseReopenEventsAcrossPosts,
        MAX(AD.PrevAnswerScoreByDate) AS MaxPrevAnswerScore,
        SUM(AD.BountyReceivedOnAnswer) AS TotalBountyReceived,
        COALESCE(UE.UserProfileViews, 0) AS ProfileViews,
        DENSE_RANK() OVER (ORDER BY UE.Reputation DESC, UE.TotalAnswersGiven DESC, UE.GoldBadges DESC) AS GlobalRankByReputationAnswers
    FROM UserEngagement AS UE
    LEFT JOIN AnswerDetails AS AD ON UE.UserId = AD.AnswerOwnerId
    LEFT JOIN QuestionContext AS PCT ON AD.QuestionId = PCT.QuestionId
    LEFT JOIN PostHistoryTimeline AS PH ON AD.AnswerId = PH.PostId OR PCT.QuestionId = PH.PostId -- Joining post history for both questions and answers
    GROUP BY
        UE.UserId, UE.DisplayName, UE.Reputation, UE.TotalQuestionsAsked, UE.TotalAnswersGiven,
        UE.GoldBadges, UE.SilverBadges, UE.BronzeBadges, UE.TotalAnswerScore, UE.UserProfileViews
)
SELECT
    UPS.UserId,
    COALESCE(UPS.DisplayName, 'AnonUser-' || UPS.UserId::varchar(10)) AS UserDisplayName,
    UPS.Reputation,
    UPS.TotalQuestionsAsked,
    UPS.TotalAnswersGiven,
    UPS.GoldBadges,
    UPS.SilverBadges,
    UPS.BronzeBadges,
    UPS.AvgAnswerScore,
    UPS.AcceptedAnswerRatio,
    UPS.UniqueQuestionsAnswered,
    UPS.TotalCommentsOnAnswers,
    UPS.AvgViewCountOfAnsweredQuestions,
    UPS.TotalPostEditEventsAcrossPosts,
    UPS.TotalCloseReopenEventsAcrossPosts,
    UPS.TotalBountyReceived,
    UPS.ProfileViews,
    UPS.MaxTagPopForAnsweredQuestions,
    UPS.MaxPrevAnswerScore,
    (
        SELECT COUNT(DISTINCT PL.RelatedPostId)
        FROM PostLinks AS PL
        WHERE PL.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = UPS.UserId AND PostTypeId = 1)
          AND PL.LinkTypeId = 3
    ) AS DuplicatedQuestionsCount,
    -- Correlated subquery to find latest comment from this user on one of their highly-scored posts
    (
        SELECT C.Text
        FROM Comments AS C
        WHERE C.UserId = UPS.UserId
          AND C.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = UPS.UserId AND Score > 100)
        ORDER BY C.CreationDate DESC
        LIMIT 1
    ) AS LatestHighScorePostComment,
    NTILE(10) OVER (ORDER BY UPS.Reputation DESC, UPS.TotalAnswersGiven DESC) AS TopDecileRanking,
    UPS.GlobalRankByReputationAnswers
FROM UserPostActivitySummary AS UPS
WHERE
    UPS.Reputation > 1000
    AND (UPS.TotalAnswersGiven > 10 OR UPS.TotalQuestionsAsked > 5)
    AND (UPS.AcceptedAnswerRatio > 0.1 OR UPS.TotalBountyReceived > 0)
    AND UPS.AvgViewCountOfAnsweredQuestions IS NOT NULL
HAVING
    (SUM(UPS.GoldBadges) + SUM(UPS.SilverBadges) * 0.5 + SUM(UPS.BronzeBadges) * 0.2) > 2 -- Composite badge score
ORDER BY
    UPS.GlobalRankByReputationAnswers ASC,
    UPS.AcceptedAnswerRatio DESC,
    UPS.TotalBountyReceived DESC
LIMIT 500;
