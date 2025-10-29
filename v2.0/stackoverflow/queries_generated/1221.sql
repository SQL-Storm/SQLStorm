-- {"query": "1221.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3168} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.ViewCount) AS AvgPostViewCount,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(B.Date) AS LatestBadgeDate,
        RANK() OVER (ORDER BY U.Reputation DESC) AS UserReputationRank
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalEdits,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 ELSE 0 END) AS HasClosureOrReopenEvent,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS LastReopenedDate,
        MIN(PH.CreationDate) AS FirstEditDate,
        MAX(PH.CreationDate) AS LatestEditDate,
        AVG(LENGTH(PH.Text)) AS AvgEditBodyLength
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20) -- Edit, Rollback, Close, Reopen, Delete, Undelete, Lock, Unlock, Protect, Unprotect
    GROUP BY PH.PostId
),
PostCommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        AVG(LENGTH(C.Text)) AS AvgCommentLength,
        COUNT(DISTINCT C.UserId) AS UniqueCommenters
    FROM Comments AS C
    GROUP BY C.PostId
),
PostVoteAnalysis AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived,
        SUM(CASE WHEN V.VoteTypeId IN (8, 9) THEN V.BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM Votes AS V
    WHERE V.VoteTypeId IN (1, 2, 3, 5, 8, 9, 10, 11, 12) -- Accepted, UpMod, DownMod, Favorite, BountyStart, BountyClose, Deletion, Undeletion, Spam
    GROUP BY V.PostId
),
TagPerformance AS (
    SELECT
        T.TagName,
        COUNT(P.Id) AS PostsWithTag,
        AVG(P.Score) AS AvgScoreForTag,
        AVG(P.ViewCount) AS AvgViewCountForTag,
        NTILE(5) OVER (ORDER BY COUNT(P.Id) DESC, AVG(P.Score) DESC) AS TagPopularityQuintile
    FROM Posts AS P
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS T(TagName)
    WHERE P.Tags IS NOT NULL AND P.Tags != '><' AND P.PostTypeId = 1 -- Only questions for tag analysis
    GROUP BY T.TagName
    HAVING COUNT(P.Id) > 50 -- Only consider sufficiently popular tags
),
QuestionDetails AS (
    SELECT
        P.Id AS QuestionId,
        P.Title AS QuestionTitle,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.OwnerUserId AS QuestionOwnerUserId,
        P.AcceptedAnswerId,
        P.ClosedDate,
        P.Tags,
        COALESCE(PL.DuplicateCount, 0) AS DuplicateLinkCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS rn_latest_question_by_user,
        LAG(P.ViewCount, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevQuestionViewCount,
        LEAD(P.ViewCount, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextQuestionViewCount
    FROM Posts AS P
    LEFT JOIN (
        SELECT RelatedPostId, COUNT(Id) AS DuplicateCount
        FROM PostLinks
        WHERE LinkTypeId = 3 -- Duplicate
        GROUP BY RelatedPostId
    ) AS PL ON P.Id = PL.RelatedPostId
    WHERE P.PostTypeId = 1 -- Only questions
),
AnswerDetails AS (
    SELECT
        P.Id AS AnswerId,
        P.ParentId AS QuestionId,
        P.Score AS AnswerScore,
        P.CreationDate AS AnswerCreationDate,
        P.OwnerUserId AS AnswerOwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.ParentId ORDER BY P.Score DESC, P.CreationDate ASC) AS rn_best_answer
    FROM Posts AS P
    WHERE P.PostTypeId = 2 -- Only answers
),
SpecialPostsFlag AS (
    SELECT P.Id AS PostId, 'High_Score_Question' AS SpecialReason
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Score > 750
    UNION ALL
    SELECT P.Id AS PostId, 'Many_Edits_Answer' AS SpecialReason
    FROM Posts P
    JOIN (
        SELECT PostId, COUNT(Id) AS EditCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6)
        GROUP BY PostId
        HAVING COUNT(Id) > 15
    ) AS PH_Edits ON P.Id = PH_Edits.PostId
    WHERE P.PostTypeId = 2
)
SELECT
    QD.QuestionId,
    QD.QuestionTitle,
    QD.QuestionCreationDate,
    QD.QuestionScore,
    QD.QuestionViewCount,
    QD.AnswerCount,
    QD.FavoriteCount,
    UE.DisplayName AS QuestionOwnerDisplayName,
    UE.Reputation AS QuestionOwnerReputation,
    UE.UserReputationRank,
    PEA.TotalEdits AS PostEditCount,
    PEA.UniqueEditors AS PostUniqueEditors,
    PCS.TotalComments AS PostCommentCount,
    PCS.TotalCommentScore AS PostTotalCommentScore,
    PVA.UpVotesReceived AS QuestionUpVotes,
    PVA.DownVotesReceived AS QuestionDownVotes,
    AD.AnswerId AS AcceptedAnswerId,
    AD.AnswerScore AS AcceptedAnswerScore,
    U_AD.DisplayName AS AcceptedAnswerOwnerDisplayName,
    TP.TagName AS TopContributingTag,
    TP.AvgScoreForTag AS TopTagAvgScore,
    TP.TagPopularityQuintile,
    COALESCE(SPF.SpecialReason, 'Normal') AS SpecialPostCategory,
    CASE
        WHEN QD.ClosedDate IS NOT NULL AND PEA.LastReopenedDate IS NOT NULL AND QD.ClosedDate < PEA.LastReopenedDate THEN 'Reopened'
        WHEN QD.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS QuestionStatus,
    CASE
        WHEN QD.AcceptedAnswerId IS NULL AND QD.AnswerCount > 0 AND QD.QuestionViewCount > 5000 THEN 'Unaccepted_HighViews'
        WHEN QD.AcceptedAnswerId IS NULL AND QD.AnswerCount = 0 AND QD.QuestionCreationDate < NOW() - INTERVAL '1 year' THEN 'NoAnswer_LongUnresolved'
        WHEN QD.AnswerCount = 0 AND PEA.TotalEdits > 5 AND QD.QuestionScore > 10 THEN 'Unanswered_HighlyEdited_Positive'
        WHEN QD.QuestionScore > 200 AND QD.FavoriteCount > 20 AND PCS.TotalComments > 30 THEN 'HighEngagement_Viral'
        ELSE 'ModerateEngagement'
    END AS QuestionEngagementCategory,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes AS V WHERE V.PostId = QD.QuestionId AND V.VoteTypeId = 5) AS UniqueFavoriters,
    (UE.Reputation > (SELECT AVG(U2.Reputation) FROM Users AS U2 WHERE EXTRACT(YEAR FROM U2.CreationDate) = EXTRACT(YEAR FROM UE.UserCreationDate) AND EXTRACT(MONTH FROM U2.CreationDate) = EXTRACT(MONTH FROM UE.UserCreationDate) AND U2.Id != UE.UserId)) AS IsAboveMonthlyAvgReputation,
    QD.QuestionViewCount - QD.NextQuestionViewCount AS ViewCountDeltaToNextPost,
    QD.QuestionViewCount - QD.PrevQuestionViewCount AS ViewCountDeltaToPrevPost,
    UPPER(LEFT(QD.QuestionTitle, 1)) AS FirstCharOfTitle,
    LENGTH(QD.QuestionTitle) AS TitleLength,
    REPLACE(REPLACE(REPLACE(COALESCE(QD.Tags, '[no-tags]'), '>', ';'), '<', ''), ';;', ';') AS CleanedTagsString,
    COALESCE(QD.QuestionScore, 0) * (1 + COALESCE(QD.FavoriteCount, 0) * 0.15 + COALESCE(PCS.TotalComments, 0) * 0.07 + COALESCE(PEA.TotalEdits, 0) * 0.03) AS WeightedPopularityScore,
    (SELECT AVG(LENGTH(C.Text)) FROM Comments C WHERE C.PostId = QD.QuestionId AND C.UserId = QD.QuestionOwnerUserId AND C.Text LIKE '%question%' IS NOT FALSE) AS AvgOwnerCommentLengthRelevant,
    QD.DuplicateLinkCount,
    CASE WHEN QD.rn_latest_question_by_user = 1 THEN TRUE ELSE FALSE END AS IsLatestQuestionByUser,
    RANK() OVER (ORDER BY QD.QuestionViewCount DESC, QD.QuestionScore DESC, WeightedPopularityScore DESC) AS GlobalEngagementRank,
    (SELECT MAX(U3.Reputation) FROM Users U3 WHERE U3.Location = UE.Location AND U3.Reputation < UE.Reputation AND U3.Id != UE.UserId) AS NextLowerReputationInSameLocation
FROM QuestionDetails AS QD
INNER JOIN UserEngagement AS UE ON QD.QuestionOwnerUserId = UE.UserId
LEFT JOIN PostEditActivity AS PEA ON QD.QuestionId = PEA.PostId
LEFT JOIN PostCommentSummary AS PCS ON QD.QuestionId = PCS.PostId
LEFT JOIN PostVoteAnalysis AS PVA ON QD.QuestionId = PVA.PostId
LEFT JOIN SpecialPostsFlag AS SPF ON QD.QuestionId = SPF.PostId
LEFT JOIN AnswerDetails AS AD ON QD.AcceptedAnswerId = AD.AnswerId AND AD.rn_best_answer = 1
LEFT JOIN Users AS U_AD ON AD.AnswerOwnerUserId = U_AD.Id
LEFT JOIN LATERAL (
    SELECT T.TagName, TP.AvgScoreForTag, TP.TagPopularityQuintile
    FROM UNNEST(string_to_array(substring(QD.Tags, 2, length(QD.Tags)-2), '><')) AS T(TagName)
    JOIN TagPerformance AS TP ON T.TagName = TP.TagName
    ORDER BY TP.AvgScoreForTag DESC, TP.PostsWithTag DESC
    LIMIT 1
) AS TP ON TRUE
WHERE
    QD.QuestionCreationDate >= '2021-01-01'
    AND UE.Reputation > 10000
    AND QD.QuestionViewCount > 1000
    AND (QD.AcceptedAnswerId IS NULL OR AD.AnswerScore < QD.QuestionScore * 0.75 OR AD.AnswerId IS NULL)
    AND PEA.TotalEdits > 5
    AND (QD.QuestionTitle LIKE 'How to optimize %' OR QD.QuestionTitle LIKE '%performance tuning%' OR QD.QuestionTitle LIKE '%scalability%' OR QD.QuestionTitle LIKE '%bottleneck%')
    AND (PCS.TotalComments > 10 OR PVA.FavoritesReceived > 5)
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_CLOSE
        WHERE PH_CLOSE.PostId = QD.QuestionId
          AND PH_CLOSE.PostHistoryTypeId = 10
          AND PH_CLOSE.Comment LIKE '101%'
          AND NOT EXISTS (
              SELECT 1 FROM PostHistory PH_REOPEN WHERE PH_REOPEN.PostId = QD.QuestionId AND PH_REOPEN.PostHistoryTypeId = 11
          )
    )
ORDER BY
    WeightedPopularityScore DESC,
    GlobalEngagementRank ASC
LIMIT 100;
