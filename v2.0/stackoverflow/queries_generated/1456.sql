-- {"query": "1456.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2621} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswerCount,
        SUM(P.ViewCount) AS TotalPostViews,
        SUM(P.Score) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        STRING_AGG(DISTINCT LOWER(QT.TagName), ',') AS TopQuestionTagsUsed,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        AVG(NULLIF(P.Score, 0)) OVER (PARTITION BY U.Id) AS AvgPostScorePerUser,
        CASE
            WHEN U.AboutMe LIKE '%data scientist%' OR U.AboutMe LIKE '%ML engineer%' OR U.AboutMe LIKE '%AI%' THEN TRUE
            ELSE FALSE
        END AS IsDataScienceRelatedProfile,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        MAX(U.LastAccessDate) AS LastUserAccessDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN ( -- Unnest tags from user's questions
        SELECT
            P_tags.Id AS PostId,
            UNNEST(string_to_array(SUBSTRING(P_tags.Tags FROM 2 FOR LENGTH(P_tags.Tags) - 2), '><')) AS TagName
        FROM Posts P_tags
        WHERE P_tags.PostTypeId = 1 AND P_tags.Tags IS NOT NULL AND LENGTH(P_tags.Tags) > 2
    ) AS QT ON P.Id = QT.PostId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.AboutMe, U.Location, U.LastAccessDate
),
PostEditAndStatusAnalysis AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount, -- Title, Body, Tags edits
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 END) AS CloseEventCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 END) AS ReopenEventCount,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate,
        MAX(PH.CreationDate) AS LastPostHistoryDate,
        STRING_AGG(DISTINCT CR.Name, ', ') FILTER (WHERE PH.PostHistoryTypeId = 10 AND CR.Name IS NOT NULL) AS DistinctCloseReasons,
        (
            SELECT U2.DisplayName
            FROM PostHistory PH2
            JOIN Users U2 ON PH2.UserId = U2.Id
            WHERE PH2.PostId = PH.PostId
              AND PH2.PostHistoryTypeId IN (4, 5, 6)
            ORDER BY PH2.CreationDate DESC
            LIMIT 1
        ) AS LastEditorDisplayNameForEdits -- Correlated subquery
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CR ON PH.Comment = CR.Id::text -- Comment field contains CloseReasonId for type 10
    GROUP BY PH.PostId
),
QuestionAnswerDerivedMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.AcceptedAnswerId,
        Q.ViewCount,
        Q.Score AS QuestionScore,
        Q.AnswerCount AS DeclaredAnswerCount,
        Q.FavoriteCount,
        Q.Title AS QuestionTitle,
        Q.Tags AS QuestionTags,
        SUM(A.Score) AS TotalAnswerScore,
        AVG(A.Score) AS AvgAnswerScore,
        MAX(A.CreationDate) AS LatestAnswerCreationDate,
        COUNT(DISTINCT A.Id) AS ActualAnswerCount,
        MAX(CASE WHEN A.Id = Q.AcceptedAnswerId THEN A.CreationDate END) AS AcceptedAnswerCreationDate,
        COUNT(DISTINCT PL_dup.RelatedPostId) AS DuplicateLinkCount,
        COUNT(DISTINCT PL_linked.RelatedPostId) AS LinkedPostCount,
        (
            SELECT COUNT(C.Id)
            FROM Comments C
            WHERE C.PostId = Q.Id
        ) AS QuestionCommentCount, -- Correlated subquery
        (
            SELECT SUM(V.BountyAmount)
            FROM Votes V
            WHERE V.PostId = Q.Id AND V.VoteTypeId = 8
        ) AS TotalBountyOffered, -- Correlated subquery
        ROW_NUMBER() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.Score DESC, Q.ViewCount DESC) AS UserQuestionRankByScoreViews, -- Window function
        LAG(Q.CreationDate) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate) AS PreviousQuestionCreationDate, -- Window function
        COALESCE(Q.ClosedDate, Q.LastActivityDate) AS EffectiveLastActivityDate -- NULL logic
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2
    LEFT JOIN PostLinks PL_dup ON Q.Id = PL_dup.PostId AND PL_dup.LinkTypeId = 3
    LEFT JOIN PostLinks PL_linked ON Q.Id = PL_linked.PostId AND PL_linked.LinkTypeId = 1
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.OwnerUserId, Q.CreationDate, Q.AcceptedAnswerId, Q.ViewCount, Q.Score, Q.AnswerCount, Q.FavoriteCount, Q.Title, Q.Tags, Q.ClosedDate, Q.LastActivityDate
),
FinalPostQuestionAnalysis AS (
    SELECT
        QAD.QuestionId,
        QAD.OwnerUserId,
        QAD.QuestionCreationDate,
        QAD.QuestionScore,
        QAD.ViewCount,
        QAD.QuestionTitle,
        QAD.QuestionTags,
        QAD.ActualAnswerCount,
        QAD.AvgAnswerScore,
        PEA.EditCount,
        PEA.CloseEventCount,
        PEA.ReopenEventCount,
        PEA.DistinctCloseReasons,
        PEA.LastEditorDisplayNameForEdits,
        QAD.DuplicateLinkCount,
        QAD.LinkedPostCount,
        QAD.QuestionCommentCount,
        QAD.TotalBountyOffered,
        QAD.UserQuestionRankByScoreViews,
        COALESCE(EXTRACT(EPOCH FROM (QAD.AcceptedAnswerCreationDate - QAD.QuestionCreationDate)) / 3600.0, 0) AS TimeToAcceptAnswerHours, -- Calculation
        (
            SELECT T.Count
            FROM Tags T
            WHERE T.TagName = (
                SELECT UNNEST(string_to_array(SUBSTRING(QAD.QuestionTags FROM 2 FOR LENGTH(QAD.QuestionTags)-2), '><'))
                ORDER BY 1 LIMIT 1
            )
        ) AS PrimaryTagGlobalQuestionCount, -- Correlated subquery for a tag's global count
        (QAD.EffectiveLastActivityDate - QAD.QuestionCreationDate) AS TimeSinceQuestionCreation, -- Date arithmetic
        CASE
            WHEN QAD.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswer'
            WHEN QAD.ActualAnswerCount > 0 THEN 'HasAnswersNoAccept'
            WHEN QAD.CloseEventCount > 0 THEN 'ClosedNoAnswers'
            ELSE 'NoAnswersOrActivity'
        END AS QuestionResolutionStatus
    FROM QuestionAnswerDerivedMetrics QAD
    LEFT JOIN PostEditAndStatusAnalysis PEA ON QAD.QuestionId = PEA.PostId
)
SELECT
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.GoldBadges,
    UA.TotalPosts,
    UA.QuestionCount,
    UA.AnswerCount,
    UA.TotalPostViews,
    UA.AvgPostScorePerUser,
    UA.IsDataScienceRelatedProfile,
    UA.UserLocation,
    UA.LastUserAccessDate,
    FPA.QuestionId,
    FPA.QuestionTitle,
    FPA.QuestionScore,
    FPA.ViewCount AS QuestionViewCount,
    FPA.EditCount AS QuestionEditCount,
    FPA.CloseEventCount AS QuestionCloseEventCount,
    FPA.ReopenEventCount AS QuestionReopenEventCount,
    FPA.DistinctCloseReasons,
    FPA.LastEditorDisplayNameForEdits,
    FPA.ActualAnswerCount,
    FPA.AvgAnswerScore,
    FPA.TimeToAcceptAnswerHours,
    FPA.TotalBountyOffered,
    FPA.PrimaryTagGlobalQuestionCount,
    FPA.DuplicateLinkCount,
    FPA.LinkedPostCount,
    FPA.QuestionCommentCount,
    FPA.UserQuestionRankByScoreViews,
    FPA.QuestionResolutionStatus,
    EXTRACT(DAY FROM FPA.TimeSinceQuestionCreation) AS DaysActiveSinceQuestionCreation, -- Date calculation
    (FPA.QuestionScore * 0.7 + FPA.ViewCount * 0.05 + FPA.ActualAnswerCount * 1.5 + FPA.TotalBountyOffered * 0.1 - FPA.CloseEventCount * 2 + UA.GoldBadges * 10) AS QuestionImpactMetric -- Complex weighted calculation
FROM UserActivity UA
JOIN FinalPostQuestionAnalysis FPA ON UA.UserId = FPA.OwnerUserId
WHERE
    UA.Reputation > 5000
    AND UA.QuestionCount > 5
    AND UA.AnswerCount > 10
    AND UA.GoldBadges >= 0
    AND FPA.QuestionScore >= 10
    AND FPA.ViewCount >= 500
    AND FPA.ActualAnswerCount >= 1
    AND FPA.TimeToAcceptAnswerHours BETWEEN 0.5 AND 120 -- Accepted within 5 days
    AND FPA.TotalBountyOffered IS NOT NULL
    AND FPA.QuestionTitle LIKE '%performance tuning%'
    AND FPA.QuestionTags LIKE '%<sql-server>%' -- String pattern matching
    AND FPA.QuestionResolutionStatus IN ('AcceptedAnswer', 'HasAnswersNoAccept')
    AND FPA.UserQuestionRankByScoreViews <= 3 -- Top 3 questions by score/views for this user
    AND UA.IsDataScienceRelatedProfile = TRUE
    AND FPA.DaysActiveSinceQuestionCreation > 7 -- Question has been active for at least a week
ORDER BY
    UA.Reputation DESC,
    FPA.QuestionImpactMetric DESC,
    FPA.QuestionCreationDate DESC
LIMIT 50;
