-- {"query": "1944.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2055}
WITH UserEngagementMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersGiven,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        COUNT(B.Id) AS TotalBadgesEarned,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AvgAnswerScore,
        MIN(P.CreationDate) AS FirstPostDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) > 5
       AND U.Reputation > 5000
),
PostModerationEvents AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (35, 36) THEN PH.CreationDate END) AS LastMigrationDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL THEN CR.Name ELSE NULL END) AS LastCloseReason,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS CloseEventCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenEventCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (35, 36) THEN PH.Id END) AS MigrationEventCount
    FROM PostHistory AS PH
    LEFT JOIN CloseReasonTypes AS CR ON (
        CASE
            WHEN PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$' THEN CAST(PH.Comment AS SMALLINT)
            ELSE NULL
        END
    ) = CR.Id
    GROUP BY PH.PostId
),
TagAnalysis AS (
    SELECT
        P.Id AS PostId,
        TRIM(x) AS TagName
    FROM Posts AS P,
    LATERAL (
      SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR (CHAR_LENGTH(P.Tags) - 2)), '><')) AS x
    ) AS t
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND CHAR_LENGTH(P.Tags) > 2
),
PostTagAggregates AS (
    SELECT
        TA.TagName,
        COUNT(DISTINCT TA.PostId) AS QuestionsTagged,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.Score) AS AverageTagScore,
        SUM(P.ViewCount) AS TotalTagViewCount,
        MAX(P.CreationDate) AS LastTagQuestionDate
    FROM TagAnalysis AS TA
    JOIN Posts AS P ON TA.PostId = P.Id
    GROUP BY TA.TagName
    HAVING COUNT(DISTINCT TA.PostId) > 100
),
PostInteractionSummary AS (
    SELECT
        COALESCE(PH.PostId, C.PostId) AS PostId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT C.Id) AS TotalComments,
        AVG(C.Score) AS AvgCommentScore,
        MAX(C.CreationDate) AS LastCommentDate
    FROM PostHistory AS PH
    FULL OUTER JOIN Comments AS C ON PH.PostId = C.PostId
    GROUP BY COALESCE(PH.PostId, C.PostId)
)
SELECT
    UEM.DisplayName,
    UEM.Reputation,
    UEM.TotalQuestionsAsked,
    UEM.TotalAnswersGiven,
    UEM.GoldBadges,
    P.Title,
    P.Score AS QuestionScore,
    P.ViewCount AS QuestionViewCount,
    P.AnswerCount AS TotalAnswersToQuestion,
    P.CreationDate AS QuestionCreationDate,
    PME.LastClosedDate,
    PME.LastReopenedDate,
    PME.LastCloseReason,
    COALESCE(PTA.TagName, 'Untagged/Minor Tags') AS PrimaryTagName,
    PTA.AverageTagScore,
    PTA.TotalTagViewCount,
    PIS.TotalHistoryEvents,
    PIS.TotalComments,
    PIS.AvgCommentScore,
    ('User activity span: ' ||
        EXTRACT(DAY FROM (UEM.LastAccessDate - UEM.UserCreationDate)) || ' days, ' ||
        EXTRACT(HOUR FROM (UEM.LastAccessDate - UEM.UserCreationDate)) || ' hours'
    ) AS UserActivitySpan,
    REPLACE(LOWER(P.Title), 'sql', 'database') AS ModifiedTitleSnippet,
    CASE
        WHEN P.ViewCount > 10000 AND P.Score > 50 THEN 'High Impact Question'
        WHEN P.ViewCount > 1000 AND P.Score > 10 THEN 'Medium Impact Question'
        ELSE 'Low Impact Question'
    END AS QuestionImpactCategory,
    RANK() OVER (PARTITION BY UEM.UserId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByUserQuestionScore,
    NTILE(100) OVER (ORDER BY P.ViewCount DESC) AS ViewCountPercentile,
    LAG(P.CreationDate, 1, UEM.FirstPostDate) OVER (PARTITION BY UEM.UserId ORDER BY P.CreationDate) AS PreviousQuestionDate,
    AVG(P.Score) OVER (PARTITION BY DATE_TRUNC('month', P.CreationDate)) AS MonthlyAvgQuestionScore,
    CASE WHEN EXISTS (
        SELECT 1
        FROM Badges AS B_inner
        WHERE B_inner.UserId = UEM.UserId
          AND B_inner.Name IN ('Autobiographer', 'Popular Question', 'Nice Answer')
          AND B_inner.Date BETWEEN P.CreationDate - INTERVAL '1 year' AND P.CreationDate + INTERVAL '1 year'
        ) THEN TRUE ELSE FALSE END AS HasRelevantBadgeAroundQuestionCreation,
    (
        SELECT COUNT(V.Id)
        FROM Votes AS V
        WHERE V.PostId = P.Id AND V.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'UpMod')
    ) AS UpVoteCountForQuestion,
    (
        SELECT COALESCE(SUM(A.Score), 0)
        FROM Posts AS A
        WHERE A.ParentId = P.Id AND A.PostTypeId = 2
    ) AS SumOfAnswerScores,
    COALESCE(P.AcceptedAnswerId, -1) AS AcceptedAnswerIdOrDefault,
    CASE WHEN P.LastEditDate IS NOT NULL AND P.LastEditDate > P.CreationDate + INTERVAL '1 day' THEN TRUE ELSE FALSE END AS WasEditedAfterFirstDay,
    CASE WHEN PME.LastClosedDate IS NOT NULL AND PME.LastReopenedDate IS NOT NULL AND PME.LastReopenedDate > PME.LastClosedDate THEN TRUE ELSE FALSE END AS WasClosedAndReopened
FROM Posts AS P
JOIN UserEngagementMetrics AS UEM ON P.OwnerUserId = UEM.UserId
LEFT JOIN PostModerationEvents AS PME ON P.Id = PME.PostId
LEFT JOIN PostTagAggregates AS PTA ON
    PTA.TagName IN (
        SELECT TA_inner.TagName FROM TagAnalysis TA_inner WHERE TA_inner.PostId = P.Id
    )
    AND P.Tags LIKE ('<' || PTA.TagName || '>')
LEFT JOIN PostInteractionSummary AS PIS ON P.Id = PIS.PostId
WHERE P.PostTypeId = 1
  AND P.CreationDate >= DATE '2020-01-01'
  AND P.Score >= 5
  AND P.ViewCount >= 100
  AND UEM.TotalQuestionsAsked >= 10
  AND (P.Body LIKE '%performance%' OR P.Title LIKE '%benchmark%')
  AND UEM.DisplayName IS NOT NULL
GROUP BY
    UEM.DisplayName,
    UEM.Reputation,
    UEM.TotalQuestionsAsked,
    UEM.TotalAnswersGiven,
    UEM.GoldBadges,
    P.Title,
    P.Score,
    P.ViewCount,
    P.AnswerCount,
    P.CreationDate,
    PME.LastClosedDate,
    PME.LastReopenedDate,
    PME.LastCloseReason,
    PTA.TagName,
    PTA.AverageTagScore,
    PTA.TotalTagViewCount,
    PIS.TotalHistoryEvents,
    PIS.TotalComments,
    PIS.AvgCommentScore,
    UEM.LastAccessDate,
    UEM.UserCreationDate,
    UEM.UserId,
    UEM.FirstPostDate,
    DATE_TRUNC('month', P.CreationDate),
    P.Id,
    P.Tags,
    P.Body,
    P.AcceptedAnswerId,
    P.LastEditDate
ORDER BY UEM.Reputation DESC, P.Score DESC, P.CreationDate DESC
LIMIT 100;