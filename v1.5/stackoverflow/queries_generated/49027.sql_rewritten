-- {"query": "49027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 2465} 
WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalQuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        SUM(CASE WHEN V_Given.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V_Given.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        SUM(U.UpVotes) AS TotalUpvotesReceivedByCommentsAndPosts
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN Votes AS V_Given ON U.Id = V_Given.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes
),
QuestionPerformance AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') AS TagArray,
        COUNT(DISTINCT PH_Edit.Id) AS EditHistoryCount,
        SUM(CASE WHEN V_Received.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PostUpvotesReceived,
        SUM(CASE WHEN V_Received.VoteTypeId = 3 THEN 1 ELSE 0 END) AS PostDownvotesReceived,
        COUNT(DISTINCT CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN PH_Close.Id END) AS CloseHistoryCount,
        COUNT(DISTINCT CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN PH_Reopen.Id END) AS ReopenHistoryCount,
        COUNT(DISTINCT L.RelatedPostId) AS LinkedQuestionsCount,
        COUNT(DISTINCT CASE WHEN L.LinkTypeId = 3 THEN L.RelatedPostId END) AS DuplicateQuestionsCount
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostHistory AS PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory AS PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    LEFT JOIN Votes AS V_Received ON P.Id = V_Received.PostId AND V_Received.VoteTypeId IN (2, 3)
    LEFT JOIN PostLinks AS L ON P.Id = L.PostId
    WHERE P.PostTypeId = 1
      AND P.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Tags
),
TagPerformance AS (
    SELECT
        QP.PostId,
        UNNEST(QP.TagArray) AS TagName,
        QP.PostScore,
        QP.ViewCount,
        QP.PostUpvotesReceived
    FROM QuestionPerformance AS QP
    WHERE QP.TagArray IS NOT NULL AND array_length(QP.TagArray, 1) > 0
),
AggregatedTagStats AS (
    SELECT
        TP.TagName,
        COUNT(DISTINCT TP.PostId) AS QuestionsInTag,
        SUM(TP.PostScore) AS TotalTagScore,
        SUM(TP.ViewCount) AS TotalTagViews,
        SUM(TP.PostUpvotesReceived) AS TotalTagUpvotes,
        AVG(TP.PostScore) AS AvgTagPostScore
    FROM TagPerformance AS TP
    GROUP BY TP.TagName
    HAVING COUNT(DISTINCT TP.PostId) > 500 AND SUM(TP.ViewCount) > 100000
),
RankedUsers AS (
    SELECT
        UCS.UserId,
        UCS.DisplayName,
        UCS.Reputation,
        UCS.TotalQuestionsPosted,
        UCS.TotalQuestionScore,
        UCS.TotalAnswerScore,
        UCS.TotalCommentsMade,
        UCS.GoldBadges,
        UCS.SilverBadges,
        SUM(QP.PostScore) AS QuestionsOwnedScore,
        SUM(QP.ViewCount) AS QuestionsOwnedViews,
        SUM(QP.AnswerCount) AS QuestionsOwnedAnswers,
        SUM(QP.CommentCount) AS QuestionsOwnedComments,
        SUM(QP.EditHistoryCount) AS QuestionsOwnedEditCount,
        SUM(QP.CloseHistoryCount) AS QuestionsOwnedCloseCount,
        SUM(QP.ReopenHistoryCount) AS QuestionsOwnedReopenCount,
        AVG(QP.PostScore) AS AvgQuestionScore,
        AVG(QP.ViewCount) AS AvgQuestionViews,
        SUM(QP.PostUpvotesReceived) AS QuestionsOwnedUpvotesReceived,
        SUM(QP.LinkedQuestionsCount) AS TotalLinkedQuestionsByOwnedPosts,
        SUM(QP.DuplicateQuestionsCount) AS TotalDuplicateQuestionsByOwnedPosts,
        (UCS.Reputation * 0.4) +
        (UCS.TotalQuestionScore * 0.25) +
        (UCS.TotalAnswerScore * 0.15) +
        (UCS.GoldBadges * 50) +
        (UCS.SilverBadges * 10) +
        (SUM(QP.PostUpvotesReceived) * 0.1) AS UserInfluenceScore,
        NTILE(10) OVER (ORDER BY (UCS.Reputation * 0.4 + UCS.TotalQuestionScore * 0.25 + UCS.TotalAnswerScore * 0.15 + UCS.GoldBadges * 50 + UCS.SilverBadges * 10 + SUM(QP.PostUpvotesReceived) * 0.1) DESC) AS InfluenceNTileRank
    FROM UserContributionSummary AS UCS
    JOIN QuestionPerformance AS QP ON UCS.UserId = QP.OwnerUserId
    WHERE UCS.TotalQuestionsPosted > 10
      AND UCS.Reputation > 5000
    GROUP BY
        UCS.UserId, UCS.DisplayName, UCS.Reputation, UCS.TotalQuestionsPosted,
        UCS.TotalQuestionScore, UCS.TotalAnswerScore, UCS.TotalCommentsMade,
        UCS.GoldBadges, UCS.SilverBadges
    HAVING SUM(QP.PostScore) > 50 AND SUM(QP.ViewCount) > 1000
)
SELECT
    RU.DisplayName,
    RU.Reputation,
    RU.InfluenceNTileRank,
    RU.TotalQuestionsPosted,
    RU.QuestionsOwnedScore,
    RU.QuestionsOwnedViews,
    RU.QuestionsOwnedAnswers,
    RU.GoldBadges,
    RU.SilverBadges,
    ATS.TagName,
    ATS.TotalTagScore,
    ATS.TotalTagViews,
    ATS.QuestionsInTag,
    ATS.AvgTagPostScore,
    SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.PostScore ELSE 0 END) AS UserTagScoreContribution,
    SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.ViewCount ELSE 0 END) AS UserTagViewContribution,
    SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.PostUpvotesReceived ELSE 0 END) AS UserTagUpvotesContribution,
    (SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.PostScore ELSE 0 END) * 0.5 +
     SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.ViewCount ELSE 0 END) * 0.005 +
     SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.PostUpvotesReceived ELSE 0 END) * 0.2) AS UserTagContributionCompositeScore,
    RANK() OVER (PARTITION BY ATS.TagName ORDER BY (SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.PostScore ELSE 0 END) * 0.5 + SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.ViewCount ELSE 0 END) * 0.005 + SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.PostUpvotesReceived ELSE 0 END) * 0.2) DESC) AS RankInTagForUser,
    ROW_NUMBER() OVER (ORDER BY RU.UserInfluenceScore DESC,
                       (SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.PostScore ELSE 0 END) * 0.5 + SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.ViewCount ELSE 0 END) * 0.005 + SUM(CASE WHEN TP.TagName = ATS.TagName THEN TP.PostUpvotesReceived ELSE 0 END) * 0.2) DESC
                       ) AS OverallUserRank
FROM RankedUsers AS RU
JOIN QuestionPerformance AS QP ON RU.UserId = QP.OwnerUserId
JOIN TagPerformance AS TP ON QP.PostId = TP.PostId
JOIN AggregatedTagStats AS ATS ON TP.TagName = ATS.TagName
WHERE RU.InfluenceNTileRank <= 3
  AND ATS.TagName IN ('python', 'javascript', 'java', 'c#', 'sql', 'html', 'css', 'php', 'reactjs', 'node.js')
GROUP BY
    RU.DisplayName, RU.Reputation, RU.InfluenceNTileRank, RU.TotalQuestionsPosted,
    RU.QuestionsOwnedScore, RU.QuestionsOwnedViews, RU.QuestionsOwnedAnswers,
    RU.GoldBadges, RU.SilverBadges, ATS.TagName, ATS.TotalTagScore, ATS.TotalTagViews, ATS.QuestionsInTag,
    ATS.AvgTagPostScore, RU.UserInfluenceScore
ORDER BY OverallUserRank ASC, RankInTagForUser ASC
LIMIT 1000;