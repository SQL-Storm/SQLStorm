-- {"query": "1692.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2677}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        MIN(P.CreationDate) AS FirstPostDate,
        MAX(P.CreationDate) AS LastPostDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostComplexMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.Score,
        P.ViewCount,
        P.FavoriteCount,
        P.Tags,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 END) AS EditCount,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.CreationDate ELSE NULL END) AS FirstEditHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.CreationDate ELSE NULL END) AS LastEditHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        (SELECT COUNT(DISTINCT T.TagName) FROM Tags T WHERE P.Tags LIKE '%' || T.TagName || '%') AS DistinctTagCount,
        AVG(C.Score) AS AvgCommentScoreForPost,
        -- Use safe aggregation for comment strings; compatible form without FILTER in some dialects
        STRING_AGG(CASE WHEN PH.Comment IS NOT NULL AND PH.Comment != '' THEN PH.Comment ELSE NULL END, '; ') AS LastEditComments
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.Title, P.CreationDate, P.LastEditDate, P.Score, P.ViewCount, P.FavoriteCount, P.Tags
),
RankedFavoriteQuestions AS (
    SELECT
        PCM.PostId,
        PCM.OwnerUserId,
        PCM.Title,
        PCM.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY PCM.OwnerUserId ORDER BY COALESCE(PCM.FavoriteCount, 0) DESC, PCM.PostCreationDate DESC) AS RankNum
    FROM PostComplexMetrics PCM
    WHERE PCM.PostTypeId = 1 AND PCM.OwnerUserId IS NOT NULL
),
HighlyEngagedUsers AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.UserCreationDate,
        UE.TotalQuestions,
        UE.AvgQuestionScore,
        UE.FirstPostDate,
        UE.LastPostDate,
        SUM(CASE WHEN B.Class = 1 AND B.TagBased = TRUE THEN 1 ELSE 0 END) AS GoldTagBadgesCount
    FROM UserEngagement UE
    LEFT JOIN Badges B ON UE.UserId = B.UserId
    WHERE UE.TotalQuestions >= 5
        AND UE.AvgQuestionScore >= 10
        AND UE.LastPostDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY UE.UserId, UE.DisplayName, UE.Reputation, UE.UserCreationDate, UE.TotalQuestions, UE.AvgQuestionScore, UE.FirstPostDate, UE.LastPostDate
    HAVING SUM(CASE WHEN B.Class = 1 AND B.TagBased = TRUE THEN 1 ELSE 0 END) >= 1
),
DuplicateLinkAnalysis AS (
    SELECT
        PL.PostId AS OriginalPostId,
        PL.RelatedPostId AS DuplicateOfPostId,
        P_Dup.Title AS DuplicatePostTitle,
        P_Dup.Score AS DuplicatePostScore,
        COALESCE(CR.Name, 'Unknown Close Reason') AS CloseReasonName
    FROM PostLinks PL
    JOIN Posts P_Dup ON PL.RelatedPostId = P_Dup.Id
    LEFT JOIN PostHistory PH_Close ON P_Dup.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CR ON PH_Close.Comment = CAST(CR.Id AS varchar)
    WHERE PL.LinkTypeId = 3
)
SELECT
    HEU.UserId,
    HEU.DisplayName,
    HEU.Reputation,
    HEU.UserCreationDate,
    HEU.TotalQuestions,
    HEU.AvgQuestionScore,
    HEU.FirstPostDate,
    HEU.LastPostDate,
    HEU.GoldTagBadgesCount,
    PCM_Q.PostId AS QuestionId,
    PCM_Q.Title AS QuestionTitle,
    PCM_Q.Score AS QuestionScore,
    PCM_Q.ViewCount AS QuestionViewCount,
    PCM_Q.FavoriteCount AS QuestionFavoriteCount,
    PCM_Q.DistinctTagCount AS QuestionDistinctTagCount,
    PCM_Q.EditCount AS QuestionEditCount,
    PCM_Q.LastEditComments AS QuestionLastEditComments,
    PCM_Q.WasClosed AS QuestionWasClosed,
    PCM_Q.WasReopened AS QuestionWasReopened,
    (
        SELECT
            AVG(C.Score)
        FROM Comments C
        JOIN Posts P_TheirAnswer ON C.PostId = P_TheirAnswer.Id
        WHERE P_TheirAnswer.PostTypeId = 2
          AND P_TheirAnswer.OwnerUserId = HEU.UserId
    ) AS AvgCommentScoreOnTheirAnswers,
    COALESCE(TRFQ.Title, 'N/A') AS TopFavoritedQuestion1Title,
    COALESCE(TRFQ.FavoriteCount, 0) AS TopFavoritedQuestion1Faves,
    COALESCE(TRFQ2.Title, 'N/A') AS TopFavoritedQuestion2Title,
    COALESCE(TRFQ2.FavoriteCount, 0) AS TopFavoritedQuestion2Faves,
    COALESCE(TRFQ3.Title, 'N/A') AS TopFavoritedQuestion3Title,
    COALESCE(TRFQ3.FavoriteCount, 0) AS TopFavoritedQuestion3Faves,
    (PCM_Q.Score * 100.0 / NULLIF(PCM_Q.ViewCount, 0) + LN(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PCM_Q.PostCreationDate)) / 3600.0)) AS QuestionHotnessMetric,
    COALESCE(DLA.DuplicateOfPostId, -1) AS LinkedDuplicatePostId,
    DLA.DuplicatePostTitle,
    DLA.CloseReasonName,
    (
        SELECT MAX(U_COLLAB.Reputation)
        FROM Users U_COLLAB
        WHERE U_COLLAB.Id IN (
            SELECT C_COLLAB.UserId
            FROM Comments C_COLLAB
            WHERE C_COLLAB.PostId = PCM_Q.PostId AND C_COLLAB.UserId IS NOT NULL AND C_COLLAB.UserId != HEU.UserId
            UNION
            SELECT P_COLLAB.OwnerUserId
            FROM Posts P_COLLAB
            WHERE P_COLLAB.ParentId = PCM_Q.PostId AND P_COLLAB.PostTypeId = 2 AND P_COLLAB.OwnerUserId IS NOT NULL AND P_COLLAB.OwnerUserId != HEU.UserId
        )
    ) AS HighestCollabReputation,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - HEU.UserCreationDate)) AS DaysSinceUserCreation,
    CASE
        WHEN PCM_Q.FirstEditHistoryDate IS NOT NULL AND PCM_Q.PostCreationDate IS NOT NULL
        THEN EXTRACT(HOUR FROM (PCM_Q.FirstEditHistoryDate - PCM_Q.PostCreationDate))
        ELSE NULL
    END AS HoursToFirstHistoryEdit,
    CASE
        WHEN PCM_Q.FirstEditHistoryDate IS NOT NULL AND PCM_Q.LastEditHistoryDate IS NOT NULL
        THEN EXTRACT(DAY FROM (PCM_Q.LastEditHistoryDate - PCM_Q.FirstEditHistoryDate))
        ELSE 0
    END AS DaysBetweenFirstAndLastEditHistory,
    -- Tag cleaning compatible across dialects: use regexp to strip leading/trailing angle brackets, then split if function available
    -- For dialects without ARRAY functions, fall back to returning original tags trimmed of outer angle brackets
    TRIM(BOTH '<>' FROM PCM_Q.Tags) AS CleanedQuestionTags
FROM HighlyEngagedUsers HEU
JOIN PostComplexMetrics PCM_Q ON HEU.UserId = PCM_Q.OwnerUserId AND PCM_Q.PostTypeId = 1
LEFT JOIN RankedFavoriteQuestions TRFQ ON HEU.UserId = TRFQ.OwnerUserId AND TRFQ.RankNum = 1
LEFT JOIN RankedFavoriteQuestions TRFQ2 ON HEU.UserId = TRFQ2.OwnerUserId AND TRFQ2.RankNum = 2
LEFT JOIN RankedFavoriteQuestions TRFQ3 ON HEU.UserId = TRFQ3.OwnerUserId AND TRFQ3.RankNum = 3
LEFT JOIN DuplicateLinkAnalysis DLA ON PCM_Q.PostId = DLA.OriginalPostId
WHERE
    PCM_Q.ViewCount > 1000
    AND (PCM_Q.WasClosed = 1 OR PCM_Q.EditCount > 5)
    AND PCM_Q.PostCreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')
ORDER BY
    HEU.Reputation DESC,
    PCM_Q.PostCreationDate DESC,
    QuestionHotnessMetric DESC
LIMIT 500;