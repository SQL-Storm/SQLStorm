WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.LastActivityDate) AS LastPostActivity,
        DATE_PART('day', AGE(U.LastAccessDate, U.CreationDate)) AS UserTenureDays
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostContentAnalysis AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.CommentCount AS QuestionCommentCount,
        Q.FavoriteCount,
        Q.Tags,
        A.Id AS AcceptedAnswerId,
        A.CreationDate AS AcceptedAnswerCreationDate,
        A.OwnerUserId AS AcceptedAnswerOwnerId,
        A.Score AS AcceptedAnswerScore,
        EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate)) / 3600.0 AS TimeToAcceptAnswerHours,
        COALESCE(
            CASE
                WHEN Q.ViewCount > 0 AND Q.FavoriteCount IS NOT NULL
                THEN CAST(Q.FavoriteCount AS NUMERIC) / Q.ViewCount
                ELSE 0
            END,
            0
        ) AS FavoriteToViewRatio,
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS NumberOfUniqueEditors,
        (SELECT MAX(LENGTH(COALESCE(PH.Text, ''))) FROM PostHistory PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId = 2) AS InitialPostBodyLength,
        (SELECT MAX(LENGTH(COALESCE(PH.Text, ''))) FROM PostHistory PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId = 5) AS LastEditedPostBodyLength,
        (LOWER(Q.Body) LIKE '%performance%' OR LOWER(Q.Body) LIKE '%optimization%') AS ContainsPerformanceKeywords
    FROM Posts Q
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id
    WHERE Q.PostTypeId = 1
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.UserId AS EditorUserId,
        LAG(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEditDate,
        LAG(PH.PostHistoryTypeId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEditType,
        RANK() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS EditRankDesc,
        COUNT(PH.Id) OVER (PARTITION BY PH.PostId) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS TotalEdits,
        CASE WHEN PH.PostHistoryTypeId = 10 THEN (SELECT CRT.Name FROM CloseReasonTypes CRT WHERE CRT.Id = CAST(PH.Comment AS INTEGER) LIMIT 1) ELSE NULL END AS CloseReason
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20)
),
AggregatedTagMetrics AS (
    SELECT
        Tag,
        COUNT(DISTINCT QuestionId) AS QuestionsWithTag,
        AVG(QuestionScore) AS AverageQuestionScoreWithTag,
        SUM(QuestionScore) AS TotalQuestionScoreWithTag,
        SUM(ViewCount) AS TotalViewCountWithTag,
        AVG(QuestionCommentCount) AS AverageCommentCountWithTag
    FROM PostContentAnalysis pca,
    LATERAL (
        SELECT TRIM(tag) AS Tag
        FROM UNNEST(string_to_array(SUBSTRING(pca.Tags FROM 2 FOR (CHAR_LENGTH(pca.Tags) - 2)), '><')) AS t(tag)
    ) AS TagsUnnested
    WHERE pca.Tags IS NOT NULL
    GROUP BY Tag
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.TotalPosts,
    UES.TotalQuestions,
    UES.TotalAnswers,
    PCA.QuestionId,
    PCA.QuestionTitle,
    PCA.QuestionCreationDate,
    PCA.QuestionScore,
    PCA.ViewCount,
    PCA.FavoriteCount,
    PCA.TimeToAcceptAnswerHours,
    PCA.FavoriteToViewRatio,
    PCA.NumberOfUniqueEditors,
    PCA.InitialPostBodyLength,
    PCA.LastEditedPostBodyLength,
    PCA.ContainsPerformanceKeywords,
    ATL.Tag AS MostFrequentTagInQuestion,
    ATM.QuestionsWithTag AS TagQuestionsCount,
    ATM.AverageQuestionScoreWithTag AS TagAvgScore,
    SUM(CASE WHEN PEA.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedCount,
    SUM(CASE WHEN PEA.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenedCount,
    AVG(CASE WHEN PEA.PostHistoryTypeId IN (4,5,6) AND PEA.PreviousEditDate IS NOT NULL THEN EXTRACT(EPOCH FROM (PEA.HistoryDate - PEA.PreviousEditDate)) / 3600.0 ELSE NULL END) AS AvgHoursBetweenEdits,
    MAX(CASE WHEN PEA.EditRankDesc = 1 THEN PEA.HistoryDate END) AS LastHistoryEventDate,
    MAX(PEA.CloseReason) AS LastCloseReason,
    (SELECT COALESCE(C.Text, 'N/A')
     FROM Comments C
     WHERE C.PostId = PCA.QuestionId AND (C.UserId = PCA.QuestionOwnerId OR (C.UserId IS NULL AND PCA.QuestionOwnerId IS NULL))
     ORDER BY C.CreationDate DESC
     LIMIT 1) AS LastOwnerComment,
    DENSE_RANK() OVER (PARTITION BY FLOOR(UES.Reputation / 10000) ORDER BY UES.TotalPostScore DESC) AS RankByPostScoreInRepRange,
    SUBSTRING(LOWER(PCA.QuestionTitle) FROM POSITION('data' IN LOWER(PCA.QuestionTitle)) FOR 8) AS QuestionTitleDataSnippet,
    CASE
        WHEN PCA.AcceptedAnswerId IS NOT NULL AND PCA.TimeToAcceptAnswerHours < 24 AND PCA.QuestionScore > 10 THEN 'Quickly Resolved & Highly Rated'
        WHEN PCA.FavoriteCount >= 50 AND PCA.ViewCount > 10000 THEN 'Popular & High Traffic'
        WHEN PCA.NumberOfUniqueEditors > 5 AND MAX(PEA.TotalEdits) > 10 THEN 'Highly Iterated Question'
        ELSE 'Standard'
    END AS QuestionCategoryClassifier
FROM UserEngagementSummary UES
INNER JOIN PostContentAnalysis PCA ON UES.UserId = PCA.QuestionOwnerId
LEFT JOIN (
    SELECT
        PostId,
        Tag,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY COUNT(*) DESC, Tag) AS rn
    FROM (
        SELECT P.Id AS PostId, TRIM(tag) AS Tag
        FROM Posts P,
        UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR (CHAR_LENGTH(P.Tags) - 2)), '><')) AS t(tag)
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL
    ) AS QuestionTags
    GROUP BY PostId, Tag
) AS ATL ON PCA.QuestionId = ATL.PostId AND ATL.rn = 1
LEFT JOIN AggregatedTagMetrics ATM ON ATL.Tag = ATM.Tag
LEFT JOIN PostEditActivity PEA ON PCA.QuestionId = PEA.PostId
WHERE
    UES.Reputation > 5000
    AND PCA.QuestionCreationDate >= DATE '2020-01-01'
    AND PCA.QuestionScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate >= DATE '2020-01-01')
    AND (PCA.Tags LIKE '%<sql>%' OR PCA.Tags LIKE '%<database>%')
    AND PCA.TimeToAcceptAnswerHours IS NOT NULL AND PCA.TimeToAcceptAnswerHours < 72
    AND UES.UserTenureDays > 365
    AND (LOWER(PCA.QuestionTitle) LIKE '%api%' OR LOWER(PCA.QuestionTitle) LIKE '%json%' OR LOWER(PCA.QuestionTitle) LIKE '%rest%')
GROUP BY
    UES.UserId, UES.DisplayName, UES.Reputation, UES.TotalPosts, UES.TotalQuestions, UES.TotalAnswers,
    PCA.QuestionId, PCA.QuestionTitle, PCA.QuestionCreationDate, PCA.QuestionScore, PCA.ViewCount,
    PCA.FavoriteCount, PCA.TimeToAcceptAnswerHours, PCA.FavoriteToViewRatio, PCA.NumberOfUniqueEditors,
    PCA.InitialPostBodyLength, PCA.LastEditedPostBodyLength, PCA.ContainsPerformanceKeywords,
    ATL.Tag, ATM.QuestionsWithTag, ATM.AverageQuestionScoreWithTag,
    PCA.AcceptedAnswerId, PCA.QuestionOwnerId, UES.TotalPostScore
HAVING COUNT(DISTINCT PEA.EditorUserId) > 1
ORDER BY
    UES.Reputation DESC,
    PCA.FavoriteToViewRatio DESC,
    ClosedCount DESC;