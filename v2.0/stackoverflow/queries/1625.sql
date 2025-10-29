WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes,
        U.DownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        MAX(P.CreationDate) AS LatestPostDate,
        MAX(C.CreationDate) AS LatestCommentDate,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM U.CreationDate) ORDER BY U.Reputation DESC) AS RankInCreationYear
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.LastAccessDate >= CAST('2024-10-01' AS date) - INTERVAL '1' YEAR
      AND U.Reputation > 5000
      AND U.AboutMe IS NOT NULL
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate
),
QuestionPerformance AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.CommentCount,
        Q.FavoriteCount,
        Q.Tags,
        Q.AcceptedAnswerId,
        AVG(A.Score) OVER (PARTITION BY Q.Id) AS AvgAnswerScore,
        MIN(A.CreationDate) OVER (PARTITION BY Q.Id) AS FirstAnswerDate,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = Q.Id AND V.VoteTypeId = 8) AS TotalBountyAmount,
        COALESCE(Q.FavoriteCount, 0) + COALESCE(Q.AnswerCount, 0) * 2 + Q.Score AS BaseEngagementMetric
    FROM Posts Q
    LEFT JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2
    WHERE Q.PostTypeId = 1
      AND Q.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2' YEAR
      AND Q.Score >= 5
      AND Q.ViewCount >= 1000
),
DuplicateAndClosedStatus AS (
    SELECT
        Q.QuestionId,
        Q.QuestionCreationDate,
        STRING_AGG(DISTINCT CAST(PL.RelatedPostId AS varchar), ',') AS DuplicatesLinked,
        MAX(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN 'Closed' ELSE 'Open' END) AS CurrentCloseStatus,
        EXISTS (
            SELECT 1
            FROM Posts AS LinkedAnswer
            JOIN PostHistory AS PH_Merge ON LinkedAnswer.Id = PH_Merge.PostId
            JOIN Users AS MergeUser ON PH_Merge.UserId = MergeUser.Id
            WHERE LinkedAnswer.ParentId = Q.QuestionId
              AND PH_Merge.PostHistoryTypeId = 37
              AND MergeUser.Reputation > 10000
              AND LinkedAnswer.PostTypeId = 2
        ) AS HasHighRepMergedAnswer
    FROM QuestionPerformance Q
    LEFT JOIN PostLinks PL ON Q.QuestionId = PL.PostId AND PL.LinkTypeId = 3
    LEFT JOIN PostHistory PH_Close ON Q.QuestionId = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    GROUP BY Q.QuestionId, Q.QuestionCreationDate
),
BadgeSummary AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(DISTINCT Name) AS UniqueBadges
    FROM Badges
    GROUP BY UserId
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    QP.QuestionId,
    QP.Title,
    QP.QuestionCreationDate,
    QP.QuestionScore,
    QP.ViewCount,
    QP.AnswerCount,
    QP.BaseEngagementMetric,
    QP.AvgAnswerScore,
    QP.FirstAnswerDate,
    QP.EditCount,
    QP.TotalBountyAmount,
    DCS.CurrentCloseStatus,
    DCS.DuplicatesLinked,
    DCS.HasHighRepMergedAnswer,
    COALESCE(BS.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(BS.SilverBadges, 0) AS UserSilverBadges,
    (UE.UpVotes - UE.DownVotes) AS NetUserVotes,
    (SELECT B.Name FROM Badges B WHERE B.UserId = UE.UserId AND B.Class = 1 ORDER BY B.Date DESC LIMIT 1) AS LatestGoldBadgeName,
    CASE
        WHEN QP.ViewCount > 50000 AND QP.AnswerCount > 10 AND QP.EditCount > 5 THEN 'High Traffic, Engaged & Evolving'
        WHEN QP.ViewCount > 10000 AND QP.BaseEngagementMetric > 50 THEN 'Popular & Interactive'
        WHEN QP.ViewCount < 5000 AND QP.EditCount > 3 AND COALESCE(BS.BronzeBadges, 0) > 0 THEN 'Niche, Evolving & Experienced User'
        ELSE 'Standard'
    END AS QuestionCategory,
    COALESCE(TRIM(SUBSTRING(QP.Tags FROM 2 FOR (POSITION('><' IN QP.Tags) - 2))), 'No_Dominant_Tag') AS DominantTag,
    (QP.BaseEngagementMetric * 1.0 / NULLIF(QP.ViewCount, 0)) AS EngagementRatioPerView,
    ROW_NUMBER() OVER (PARTITION BY UE.UserId ORDER BY QP.QuestionScore DESC, QP.ViewCount DESC) AS UserQuestionRank,
    EXTRACT(DAY FROM (QP.QuestionCreationDate - LAG(QP.QuestionCreationDate, 1) OVER (PARTITION BY UE.UserId ORDER BY QP.QuestionCreationDate))) AS DaysSincePreviousQuestion,
    EXTRACT(DAY FROM (LEAD(QP.QuestionCreationDate, 1) OVER (PARTITION BY UE.UserId ORDER BY QP.QuestionCreationDate) - QP.QuestionCreationDate)) AS DaysUntilNextQuestion
FROM UserEngagement UE
JOIN QuestionPerformance QP ON UE.UserId = QP.OwnerUserId
LEFT JOIN DuplicateAndClosedStatus DCS ON QP.QuestionId = DCS.QuestionId
LEFT JOIN BadgeSummary BS ON UE.UserId = BS.UserId
WHERE UE.Reputation > 10000
  AND (QP.FirstAnswerDate IS NOT NULL AND QP.FirstAnswerDate < QP.QuestionCreationDate + INTERVAL '1' DAY)
  AND (QP.TotalBountyAmount IS NULL OR QP.TotalBountyAmount > 0)
  AND (QP.AcceptedAnswerId IS NOT NULL OR QP.CommentCount > 5)
  AND (QP.Tags LIKE '%<sql>%' OR QP.Tags LIKE '%<database>%' OR QP.Tags LIKE '%<performance>%')
  AND QP.EditCount >= 1
  AND UE.LatestPostDate IS NOT NULL
  AND (COALESCE(BS.SilverBadges, 0) > 0
       AND UE.LastAccessDate >= CAST('2024-10-01' AS date) - INTERVAL '3' MONTH
       AND (QP.BaseEngagementMetric * 1.0 / NULLIF(QP.ViewCount, 0)) > 0.01)
  AND NOT (DCS.CurrentCloseStatus = 'Closed' AND DCS.DuplicatesLinked IS NOT NULL AND QP.AcceptedAnswerId IS NULL)
ORDER BY UE.Reputation DESC, QP.BaseEngagementMetric DESC, QP.QuestionCreationDate DESC
LIMIT 500;