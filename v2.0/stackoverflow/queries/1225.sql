-- {"query": "1225.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2475}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COALESCE(SUM(P.Score), 0) AS TotalPostsScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalQuestionsViewCount,
        (U.Reputation / 1000.0) * (U.UpVotes - U.DownVotes + 1.0) +
        (EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (3600.0 * 24 * 365.25)) AS CompositeActivityScore,
        (SELECT MIN(B_INNER.Date) FROM Badges AS B_INNER WHERE B_INNER.UserId = U.Id AND B_INNER.Name = 'Editor' AND B_INNER.Class = 2) AS FirstSilverEditorBadgeDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    WHERE U.Reputation > 1000
      AND U.CreationDate >= TIMESTAMP '2018-01-01'
      AND U.LastAccessDate >= TIMESTAMP '2023-01-01'
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 10
),
QuestionDetailedMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Title AS QuestionTitle,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount,
        Q.CreationDate AS QuestionCreationDate,
        Q.LastActivityDate AS QuestionLastActivityDate,
        Q.Tags,
        COALESCE(A.Score, 0) AS AcceptedAnswerScore,
        A.OwnerUserId AS AcceptedAnswerOwnerId,
        A.CreationDate AS AcceptedAnswerCreationDate,
        PH_Close.CreationDate AS CloseHistoryDate,
        COALESCE(CRC.Name, 'N/A') AS CloseReason,
        CASE
            WHEN Q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN Q.ClosedDate IS NOT NULL THEN 'Closed by Users'
            ELSE 'Open'
        END AS QuestionStatus,
        (
            SELECT COALESCE(LEU.DisplayName, P_INNER.LastEditorDisplayName, 'Community')
            FROM Posts AS P_INNER
            LEFT JOIN Users AS LEU ON P_INNER.LastEditorUserId = LEU.Id
            WHERE P_INNER.Id = Q.Id
            ORDER BY P_INNER.LastEditDate DESC NULLS LAST
            LIMIT 1
        ) AS MostRecentEditorDisplayName,
        EXISTS (
            SELECT 1
            FROM PostHistory AS PH_REOPEN
            WHERE PH_REOPEN.PostId = Q.Id AND PH_REOPEN.PostHistoryTypeId = 11
        ) AS HasBeenReopened,
        Q.AcceptedAnswerId
    FROM Posts AS Q
    LEFT JOIN Posts AS A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2
    LEFT JOIN PostHistory AS PH_Close ON Q.Id = PH_Close.PostId
        AND PH_Close.PostHistoryTypeId = 10
        AND PH_Close.Id = (SELECT MAX(PH_MAX.Id) FROM PostHistory AS PH_MAX WHERE PH_MAX.PostId = Q.Id AND PH_MAX.PostHistoryTypeId = 10)
    LEFT JOIN CloseReasonTypes AS CRC ON PH_Close.Comment = CAST(CRC.Id AS varchar)
    WHERE Q.PostTypeId = 1
      AND Q.Score > 0
      AND Q.ViewCount > 50
),
TagPerformance AS (
    SELECT
        QD.QuestionId,
        TRIM(UNNEST(string_to_array(SUBSTRING(QD.Tags FROM 2 FOR (LENGTH(QD.Tags) - 2)), '><'))) AS TagName,
        QD.QuestionScore,
        QD.QuestionViewCount
    FROM QuestionDetailedMetrics AS QD
    WHERE QD.Tags IS NOT NULL AND LENGTH(QD.Tags) > 2
),
ModeratorBadges AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS GoldAndSilverBadges
    FROM Badges AS B
    WHERE B.Class IN (1, 2)
      AND B.Name IN ('Disciplined', 'Civic Duty', 'Reviewer', 'Strunk & White')
    GROUP BY B.UserId
    HAVING COUNT(B.Id) >= 2
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPostsOwned,
    UE.TotalQuestionsOwned,
    UE.TotalAnswersOwned,
    UE.TotalPostsScore,
    UE.CompositeActivityScore,
    UE.FirstSilverEditorBadgeDate,
    QDM.QuestionId,
    QDM.QuestionTitle,
    QDM.QuestionScore,
    QDM.QuestionViewCount,
    QDM.AnswerCount,
    QDM.QuestionStatus,
    QDM.CloseReason,
    QDM.AcceptedAnswerScore,
    QDM.MostRecentEditorDisplayName,
    QDM.HasBeenReopened,
    TP.TagName,
    T.Count AS GlobalTagUsageCount,
    LT.Name AS RelatedPostLinkType,
    PL.RelatedPostId AS DuplicateOrLinkedPostId,
    MB.GoldAndSilverBadges AS UserModeratorBadgesCount,
    RANK() OVER (PARTITION BY UE.UserId ORDER BY QDM.QuestionScore DESC, QDM.QuestionCreationDate DESC) AS QuestionRankByOwner,
    AVG(QDM.QuestionScore) OVER (PARTITION BY TP.TagName) AS AvgQuestionScorePerTag,
    SUM(QDM.QuestionScore) OVER (ORDER BY QDM.QuestionCreationDate ASC, UE.UserId ASC) AS RunningTotalQuestionScore,
    QDM.QuestionScore * (1.0 + COALESCE(QDM.AcceptedAnswerScore, 0.0) / NULLIF(QDM.QuestionViewCount, 0.0)) AS WeightedQuestionEffectiveness,
    (EXTRACT(EPOCH FROM (QDM.QuestionLastActivityDate - QDM.QuestionCreationDate)) / (3600.0 * 24)) AS DaysSinceQuestionActivity,
    COALESCE(UPPER(SUBSTRING(TRIM(QDM.QuestionTitle) FROM 1 FOR 1)), '#') AS FirstCharOfTitle,
    CASE
        WHEN QDM.QuestionStatus = 'Closed by Users' AND QDM.HasBeenReopened THEN 'Closed-Then-Reopened'
        WHEN QDM.QuestionStatus = 'Closed by Users' AND QDM.CloseReason = 'Duplicate' THEN 'Closed-Duplicate'
        WHEN QDM.AnswerCount = 0 AND QDM.QuestionCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months') THEN 'Stale Unanswered'
        WHEN QDM.AcceptedAnswerId IS NOT NULL AND QDM.AcceptedAnswerScore >= QDM.QuestionScore / 2 THEN 'Well-Answered'
        WHEN QDM.QuestionScore > 50 AND QDM.QuestionViewCount > 1000 THEN 'High-Visibility Question'
        ELSE 'General Activity'
    END AS QuestionLifecycleStatus,
    (
        SELECT COUNT(C.Id)
        FROM Comments AS C
        WHERE C.PostId = QDM.QuestionId
          AND C.Score > 0
          AND C.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 months')
    ) AS RecentPositiveCommentsCount,
    QDM.QuestionCreationDate
FROM UserEngagement AS UE
INNER JOIN QuestionDetailedMetrics AS QDM ON UE.UserId = QDM.QuestionOwnerId
LEFT JOIN TagPerformance AS TP ON QDM.QuestionId = TP.QuestionId
LEFT JOIN Tags AS T ON TP.TagName = T.TagName
LEFT JOIN PostLinks AS PL ON QDM.QuestionId = PL.PostId
LEFT JOIN LinkTypes AS LT ON PL.LinkTypeId = LT.Id
LEFT JOIN ModeratorBadges AS MB ON UE.UserId = MB.UserId
WHERE
    UE.CompositeActivityScore > 500
    AND QDM.QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
    AND (TP.TagName LIKE '%sql%' OR TP.TagName LIKE '%query%' OR TP.TagName LIKE '%database%')
    AND QDM.QuestionScore > 10
    AND QDM.AcceptedAnswerScore > 0
    AND UE.FirstSilverEditorBadgeDate IS NOT NULL
GROUP BY
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.TotalPostsOwned,
    UE.TotalQuestionsOwned,
    UE.TotalAnswersOwned,
    UE.TotalPostsScore,
    UE.CompositeActivityScore,
    UE.FirstSilverEditorBadgeDate,
    QDM.QuestionId,
    QDM.QuestionTitle,
    QDM.QuestionScore,
    QDM.QuestionViewCount,
    QDM.AnswerCount,
    QDM.QuestionStatus,
    QDM.CloseReason,
    QDM.AcceptedAnswerScore,
    QDM.MostRecentEditorDisplayName,
    QDM.HasBeenReopened,
    QDM.AcceptedAnswerId,
    QDM.QuestionLastActivityDate,
    TP.TagName,
    T.Count,
    LT.Name,
    PL.RelatedPostId,
    MB.GoldAndSilverBadges,
    QDM.QuestionCreationDate
ORDER BY
    UE.Reputation DESC,
    WeightedQuestionEffectiveness DESC,
    DaysSinceQuestionActivity ASC
LIMIT 10000;