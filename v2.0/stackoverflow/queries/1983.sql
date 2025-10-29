-- {"query": "1983.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2981}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        CASE
            WHEN U.Reputation > 150000 THEN 'Diamond Tier'
            WHEN U.Reputation > 75000 THEN 'Platinum Tier'
            WHEN U.Reputation > 30000 THEN 'Gold Tier'
            WHEN U.Reputation > 15000 THEN 'Silver Tier'
            ELSE 'Bronze Tier'
        END AS ReputationTier,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (SELECT MAX(PH_inner.CreationDate) FROM PostHistory AS PH_inner WHERE PH_inner.UserId = U.Id) AS LastHistoryActivity,
        (SELECT AVG(C_inner.Score) FROM Comments AS C_inner WHERE C_inner.UserId = U.Id AND C_inner.Score > 0) AS AvgUserPositiveCommentScore
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    WHERE U.Id IN (
        SELECT DISTINCT OwnerUserId
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
          AND PostTypeId IN (1,2)
          AND CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5 year'
    )
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location
    HAVING U.Reputation > 10000 AND COUNT(DISTINCT B.Id) > 10
),
PostQualityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.Body,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        (COALESCE(P.Score, 0) * 0.45 + COALESCE(P.ViewCount, 0) * 0.1 + COALESCE(P.FavoriteCount, 0) * 0.35 + COALESCE(P.AnswerCount, 0) * 0.1) AS DerivedEngagementScore,
        (CHAR_LENGTH(COALESCE(P.Body, '')) - CHAR_LENGTH(REPLACE(COALESCE(P.Body, ''), '<code>', ''))) / NULLIF(CHAR_LENGTH('<code>'),0) AS CodeBlockHeuristic,
        (SELECT COUNT(DISTINCT PH_edit.UserId) FROM PostHistory AS PH_edit WHERE PH_edit.PostId = P.Id AND PH_edit.PostHistoryTypeId IN (4, 5, 6)) AS UniqueEditorsCount,
        ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByUserAndType,
        LAG(P.CreationDate, 1) OVER(PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostDate,
        (SELECT STRING_AGG(lower(replace(replace(replace(tag_val, '-', '_'), '.', ''), ',', '')), ', ' ORDER BY tag_val)
         FROM (
             SELECT TRIM(x) AS tag_val
             FROM (
                 SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR GREATEST(0, CHAR_LENGTH(P.Tags)-2)), '><')) AS x
             ) AS t
         ) AS tags_sub
         WHERE CHAR_LENGTH(tag_val) > 0
        ) AS CleanedTagsString,
        (SELECT COUNT(1) FROM PostLinks PL_inner WHERE PL_inner.PostId = P.Id AND PL_inner.LinkTypeId = 3) AS DuplicateLinkCount
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.CreationDate BETWEEN CAST('2020-01-01' AS date) AND CAST('2023-12-31' AS date)
      AND P.Score > 10
      AND P.PostTypeId IN (1, 2)
      AND CHAR_LENGTH(COALESCE(P.Body, '')) > 100
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.Title, P.Body, P.Tags, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.AcceptedAnswerId, P.ParentId
),
PostHistoryDetails AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PH.PostHistoryTypeId,
        PH.Comment,
        PH.UserId AS HistoryUserId,
        CR.Name AS CloseReasonName,
        CAST(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE 'CloseReasonId:%' THEN SUBSTRING(PH.Comment FROM CHAR_LENGTH('CloseReasonId:') + 1) ELSE NULL END AS SMALLINT) AS CloseReasonId,
        ROW_NUMBER() OVER(PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn
    FROM PostHistory AS PH
    LEFT JOIN CloseReasonTypes AS CR ON PH.PostHistoryTypeId = 10
        AND PH.Comment LIKE 'CloseReasonId:%'
        AND CAST(SUBSTRING(PH.Comment FROM CHAR_LENGTH('CloseReasonId:') + 1) AS SMALLINT) = CR.Id
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 35, 36)
)
(
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.ReputationTier,
        UAS.UserCreationDate,
        UAS.UserLocation,
        PQM.PostId,
        'Question' AS PostCategory,
        PQM.Title AS PostTitle,
        PQM.PostScore,
        PQM.ViewCount,
        PQM.DerivedEngagementScore,
        PQM.CodeBlockHeuristic,
        PQM.CleanedTagsString,
        PHD.CloseReasonName AS LatestCloseReason,
        (
            SELECT COALESCE(SUM(V_inner.BountyAmount), 0)
            FROM Votes V_inner
            WHERE V_inner.PostId = PQM.PostId AND V_inner.VoteTypeId = 8
        ) AS TotalBountyAmount,
        CAST(NULLIF(PQM.PostScore, 0) AS NUMERIC) / NULLIF(PQM.ViewCount, 0) AS ScorePerViewRatio,
        RANK() OVER (PARTITION BY UAS.ReputationTier ORDER BY PQM.DerivedEngagementScore DESC, PQM.PostCreationDate DESC) AS RankWithinTier,
        'High Engagement Question Analysis' AS AnalysisType,
        PHD.CloseReasonId AS LatestCloseReasonId,
        EXTRACT(HOUR FROM (PQM.PostCreationDate - PQM.PreviousPostDate)) AS HoursSincePreviousPost
    FROM UserActivitySummary AS UAS
    INNER JOIN PostQualityMetrics AS PQM ON UAS.UserId = PQM.OwnerUserId
    LEFT JOIN PostHistoryDetails AS PHD ON PQM.PostId = PHD.PostId AND PHD.rn = 1
    WHERE
        PQM.PostTypeId = 1
        AND PQM.DerivedEngagementScore > 120
        AND PQM.CodeBlockHeuristic > 1
        AND PQM.UniqueEditorsCount > 2
        AND UAS.ReputationTier IN ('Diamond Tier', 'Platinum Tier', 'Gold Tier')
        AND (PQM.CleanedTagsString LIKE '%sql%' OR PQM.CleanedTagsString LIKE '%database%')
        AND NOT EXISTS (
            SELECT 1 FROM PostHistory PH_deleted WHERE PH_deleted.PostId = PQM.PostId AND PH_deleted.PostHistoryTypeId = 12
        )
        AND (PHD.CloseReasonId IS NULL OR PHD.CloseReasonId NOT IN (101, 102))
        AND PQM.PostCreationDate > UAS.UserCreationDate + INTERVAL '3 months'
)
UNION ALL
(
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.ReputationTier,
        UAS.UserCreationDate,
        UAS.UserLocation,
        PQM.PostId,
        'Answer' AS PostCategory,
        PQM.Title AS PostTitle,
        PQM.PostScore,
        (SELECT Q.ViewCount FROM Posts Q WHERE Q.Id = PQM.ParentId) AS QuestionViewCount,
        PQM.DerivedEngagementScore,
        PQM.CodeBlockHeuristic,
        PQM.CleanedTagsString,
        NULL AS LatestCloseReason,
        NULL AS TotalBountyAmount,
        CAST(NULLIF(PQM.PostScore, 0) AS NUMERIC) / (
            SELECT NULLIF(Q.ViewCount, 0) FROM Posts Q WHERE Q.Id = PQM.ParentId
        ) AS AnswerScoreToQuestionViewRatio,
        RANK() OVER (PARTITION BY UAS.ReputationTier ORDER BY PQM.PostScore DESC, PQM.PostCreationDate DESC) AS RankWithinTier,
        'Highly Accepted Answer Analysis' AS AnalysisType,
        NULL AS LatestCloseReasonId,
        EXTRACT(HOUR FROM (PQM.PostCreationDate - PQM.PreviousPostDate)) AS HoursSincePreviousPost
    FROM UserActivitySummary AS UAS
    INNER JOIN PostQualityMetrics AS PQM ON UAS.UserId = PQM.OwnerUserId
    INNER JOIN Posts AS AcceptedQuestion ON PQM.ParentId = AcceptedQuestion.Id AND AcceptedQuestion.AcceptedAnswerId = PQM.PostId
    WHERE
        PQM.PostTypeId = 2
        AND PQM.PostScore > 75
        AND PQM.PostCreationDate > UAS.UserCreationDate + INTERVAL '6 months'
        AND UAS.ReputationTier IN ('Diamond Tier', 'Platinum Tier', 'Gold Tier')
        AND (PQM.CleanedTagsString LIKE '%javascript%' OR PQM.CleanedTagsString LIKE '%frontend%')
        AND EXISTS (
            SELECT 1 FROM Comments C_inner WHERE C_inner.PostId = PQM.PostId AND LOWER(C_inner.Text) LIKE '%thank%'
        )
        AND CHAR_LENGTH(TRIM(COALESCE(PQM.Body, ''))) > 200
)
ORDER BY
    Reputation DESC,
    DerivedEngagementScore DESC NULLS LAST,
    AnalysisType ASC,
    PostCategory DESC
LIMIT 250 OFFSET 50;