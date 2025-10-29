WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes + U.DownVotes AS TotalVotesGiven,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        COALESCE(AVG(C.Score), 0) AS AverageCommentScoreGiven,
        NTILE(5) OVER (ORDER BY U.Reputation DESC, U.UpVotes DESC) AS ReputationTier
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes
),
QuestionMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        Q.Title,
        Q.Tags,
        A.Id AS AcceptedAnswerId,
        A.Score AS AcceptedAnswerScore,
        (SELECT AVG(Ans.Score) FROM Posts Ans WHERE Ans.ParentId = Q.Id AND Ans.PostTypeId = 2 AND Ans.Score IS NOT NULL) AS AverageAnswerScore,
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS DistinctEditorsCount,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS LastEditHistoryDate
    FROM Posts Q
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id AND A.PostTypeId = 2
    LEFT JOIN PostHistory PH ON Q.Id = PH.PostId
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.OwnerUserId, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.Title, Q.Tags, A.Id, A.Score
),
RankedQuestionsBase AS (
    SELECT
        QM.QuestionId,
        (QM.QuestionScore * 0.7 + COALESCE(QM.FavoriteCount, 0) * 4.5 + QM.AnswerCount * 2.5 + COALESCE(QM.AverageAnswerScore, 0) * 1.5) AS ScoreBasedEngagement,
        (QM.ViewCount * 0.25 + QM.AnswerCount * 1.7 + QM.QuestionScore * 0.35 + COALESCE(QM.FavoriteCount, 0) * 2) AS ViewBasedEngagement,
        'HighScoreEngagement' AS RankCategory
    FROM QuestionMetrics QM
    WHERE QM.QuestionCreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 year'
      AND QM.Title IS NOT NULL
      AND QM.QuestionScore > 15
    UNION
    SELECT
        QM.QuestionId,
        (QM.QuestionScore * 0.7 + COALESCE(QM.FavoriteCount, 0) * 4.5 + QM.AnswerCount * 2.5 + COALESCE(QM.AverageAnswerScore, 0) * 1.5) AS ScoreBasedEngagement,
        (QM.ViewCount * 0.25 + QM.AnswerCount * 1.7 + QM.QuestionScore * 0.35 + COALESCE(QM.FavoriteCount, 0) * 2) AS ViewBasedEngagement,
        'HighViewActivity' AS RankCategory
    FROM QuestionMetrics QM
    WHERE QM.QuestionCreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 year'
      AND QM.Title IS NOT NULL
      AND QM.ViewCount > 2500
),
RecentActivityRank AS (
    SELECT
        RQ.QuestionId,
        QM.Title,
        QM.QuestionCreationDate,
        QM.LastEditHistoryDate,
        QM.QuestionScore,
        QM.ViewCount,
        QM.AnswerCount,
        QM.FavoriteCount,
        COALESCE(QM.AverageAnswerScore, 0) AS CalculatedAvgAnswerScore,
        CASE
            WHEN RQ.RankCategory = 'HighScoreEngagement' THEN RQ.ScoreBasedEngagement
            ELSE RQ.ViewBasedEngagement
        END AS EngagementScore,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM QM.QuestionCreationDate), EXTRACT(MONTH FROM QM.QuestionCreationDate) ORDER BY (CASE WHEN RQ.RankCategory = 'HighScoreEngagement' THEN RQ.ScoreBasedEngagement ELSE RQ.ViewBasedEngagement END) DESC) AS MonthlyPopularityRank,
        RANK() OVER (ORDER BY (CASE WHEN RQ.RankCategory = 'HighScoreEngagement' THEN RQ.ScoreBasedEngagement ELSE RQ.ViewBasedEngagement END) DESC, QM.ViewCount DESC, QM.QuestionScore DESC) AS OverallScoreRank,
        RQ.RankCategory
    FROM RankedQuestionsBase RQ
    JOIN QuestionMetrics QM ON RQ.QuestionId = QM.QuestionId
)
SELECT
    RAR.QuestionId,
    RAR.Title,
    U.DisplayName AS QuestionOwnerDisplayName,
    UE.Reputation AS OwnerReputation,
    UE.ReputationTier,
    RAR.QuestionCreationDate,
    RAR.LastEditHistoryDate,
    RAR.QuestionScore,
    RAR.ViewCount,
    RAR.AnswerCount,
    COALESCE(RAR.FavoriteCount, 0) AS FavoriteCount,
    RAR.CalculatedAvgAnswerScore,
    RAR.EngagementScore,
    RAR.MonthlyPopularityRank,
    RAR.OverallScoreRank,
    RAR.RankCategory,
    COALESCE(STRING_AGG(DISTINCT T.TagName, ', ' ORDER BY T.TagName), 'no_tags_found') AS RelatedTags,
    (
        SELECT MAX(C.CreationDate)
        FROM Comments C
        WHERE C.PostId = RAR.QuestionId
    ) AS LatestCommentDate,
    CASE
        WHEN UE.HasGoldBadge = 1 AND RAR.EngagementScore > 200 AND RAR.OverallScoreRank <= 500 THEN 'Elite Contributor - High Impact Question'
        WHEN UE.TotalBadges >= 75 AND RAR.OverallScoreRank <= 2000 AND UE.ReputationTier = 1 THEN 'Experienced User - Top Tier Question'
        WHEN RAR.MonthlyPopularityRank <= 250 AND RAR.ViewCount > 5000 THEN 'Monthly Trending Question with High Views'
        WHEN RAR.RankCategory = 'HighViewActivity' AND RAR.ViewCount > 10000 THEN 'Viral Question (High Views)'
        ELSE 'General Highly Engaged Question'
    END AS QuestionCategory,
    'https://stackoverflow.com/questions/' || RAR.QuestionId AS QuestionURL,
    SQ_PL.LinkedPostCount,
    SQ_PL.DuplicatePostCount,
    LAG(RAR.QuestionScore, 1, 0) OVER (PARTITION BY U.Id ORDER BY RAR.QuestionCreationDate) AS PreviousQuestionScoreByOwner,
    LEAD(RAR.QuestionScore, 1, 0) OVER (PARTITION BY U.Id ORDER BY RAR.QuestionCreationDate) AS NextQuestionScoreByOwner,
    (
        SELECT COUNT(DISTINCT V.UserId)
        FROM Votes V
        WHERE V.PostId = RAR.QuestionId AND V.VoteTypeId = 5
          AND V.CreationDate BETWEEN RAR.QuestionCreationDate AND COALESCE(RAR.LastEditHistoryDate, CAST('2024-10-01 12:34:56' AS TIMESTAMP))
    ) AS FavoritesDuringActivePeriod,
    COALESCE(QM.DistinctEditorsCount, 0) AS TotalDistinctEditors
FROM RecentActivityRank RAR
JOIN QuestionMetrics QM ON RAR.QuestionId = QM.QuestionId
JOIN Users U ON QM.OwnerUserId = U.Id
LEFT JOIN UserEngagement UE ON U.Id = UE.UserId
LEFT JOIN LATERAL (
    SELECT
        COUNT(CASE WHEN PL.LinkTypeId = 1 THEN 1 END) AS LinkedPostCount,
        COUNT(CASE WHEN PL.LinkTypeId = 3 THEN 1 END) AS DuplicatePostCount
    FROM PostLinks PL
    WHERE PL.PostId = RAR.QuestionId
) SQ_PL ON TRUE
LEFT JOIN Tags T ON QM.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
WHERE
    U.Views > 7500
    AND U.DisplayName IS NOT NULL
    AND RAR.EngagementScore > (SELECT AVG(EngagementScore) FROM RecentActivityRank WHERE QuestionCreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 year') * 1.5
    AND (
        RAR.MonthlyPopularityRank <= 750
        OR RAR.OverallScoreRank <= 7500
        OR UE.ReputationTier = 1
    )
    AND (RAR.QuestionId NOT IN (
        SELECT P.Id
        FROM Posts P
        WHERE P.ClosedDate IS NOT NULL AND P.PostTypeId = 1
          AND P.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    ))
    AND (
        QM.Tags ILIKE '%<sql>%'
        OR QM.Tags ILIKE '%<database>%'
        OR QM.Tags ILIKE '%<performance>%'
        OR QM.Tags ILIKE '%<optimization>%'
    )
    AND RAR.QuestionScore IS NOT NULL
    AND RAR.QuestionCreationDate IS NOT NULL
    AND (
        (UE.AverageCommentScoreGiven > 3 AND UE.TotalBadges > 20)
        OR (QM.DistinctEditorsCount > 1 AND RAR.LastEditHistoryDate IS NOT NULL)
        OR (SQ_PL.LinkedPostCount > 0 OR SQ_PL.DuplicatePostCount > 0)
    )
GROUP BY
    RAR.QuestionId,
    RAR.Title,
    U.DisplayName,
    UE.Reputation,
    UE.ReputationTier,
    RAR.QuestionCreationDate,
    RAR.LastEditHistoryDate,
    RAR.QuestionScore,
    RAR.ViewCount,
    RAR.AnswerCount,
    RAR.FavoriteCount,
    RAR.CalculatedAvgAnswerScore,
    RAR.EngagementScore,
    RAR.MonthlyPopularityRank,
    RAR.OverallScoreRank,
    RAR.RankCategory,
    SQ_PL.LinkedPostCount,
    SQ_PL.DuplicatePostCount,
    U.Id,
    UE.HasGoldBadge,
    UE.AverageCommentScoreGiven,
    UE.TotalBadges,
    QM.DistinctEditorsCount,
    T.Id,
    T.TagName
HAVING
    COUNT(DISTINCT T.Id) >= 1
    AND (MAX(QM.LastEditHistoryDate) IS NOT NULL)
ORDER BY
    RAR.EngagementScore DESC,
    UE.Reputation DESC,
    RAR.QuestionCreationDate DESC
LIMIT 1000;