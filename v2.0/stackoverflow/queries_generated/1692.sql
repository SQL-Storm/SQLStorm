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
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 END) AS EditCount, -- Count of specific edit-related history types
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.CreationDate ELSE NULL END) AS FirstEditHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.CreationDate ELSE NULL END) AS LastEditHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed, -- Post Closed
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened, -- Post Reopened
        (SELECT COUNT(DISTINCT T.TagName) FROM Tags T WHERE P.Tags LIKE '%' || T.TagName || '%') AS DistinctTagCount, -- Correlated subquery for tag count
        AVG(C.Score) AS AvgCommentScoreForPost,
        STRING_AGG(CASE WHEN PH.Comment IS NOT NULL AND PH.Comment != '' THEN PH.Comment ELSE NULL END, '; ') FILTER (WHERE PH.Comment IS NOT NULL AND PH.Comment != '') AS LastEditComments
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
        ROW_NUMBER() OVER (PARTITION BY PCM.OwnerUserId ORDER BY COALESCE(PCM.FavoriteCount, 0) DESC, PCM.CreationDate DESC) AS RankNum
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
        AND UE.LastPostDate > (NOW() - INTERVAL '1 year')
    GROUP BY UE.UserId, UE.DisplayName, UE.Reputation, UE.UserCreationDate, UE.TotalQuestions, UE.AvgQuestionScore, UE.FirstPostDate, UE.LastPostDate
    HAVING SUM(CASE WHEN B.Class = 1 AND B.TagBased = TRUE THEN 1 ELSE 0 END) >= 1
),
DuplicateLinkAnalysis AS (
    SELECT
        PL.PostId AS OriginalPostId,
        PL.RelatedPostId AS DuplicateOfPostId,
        P_Dup.Title AS DuplicatePostTitle,
        P_Dup.Score AS DuplicatePostScore,
        COALESCE(CR.Name, 'Unknown Close Reason') AS CloseReasonName -- NULL logic with COALESCE
    FROM PostLinks PL
    JOIN Posts P_Dup ON PL.RelatedPostId = P_Dup.Id
    LEFT JOIN PostHistory PH_Close ON P_Dup.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10 -- Post Closed history
    LEFT JOIN CloseReasonTypes CR ON PH_Close.Comment = CR.Id::varchar -- Complicated predicate with type casting
    WHERE PL.LinkTypeId = 3 -- Duplicate link type
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
    -- Correlated subquery for average comment score on all their answers
    (
        SELECT
            AVG(C.Score)
        FROM Comments C
        JOIN Posts P_TheirAnswer ON C.PostId = P_TheirAnswer.Id
        WHERE P_TheirAnswer.PostTypeId = 2 -- It's an answer
          AND P_TheirAnswer.OwnerUserId = HEU.UserId -- It's an answer by the current HEU user
    ) AS AvgCommentScoreOnTheirAnswers,
    -- Top 3 favorited questions per user using LEFT JOINs to RankedFavoriteQuestions CTE
    COALESCE(TRFQ.Title, 'N/A') AS TopFavoritedQuestion1Title,
    COALESCE(TRFQ.FavoriteCount, 0) AS TopFavoritedQuestion1Faves,
    COALESCE(TRFQ2.Title, 'N/A') AS TopFavoritedQuestion2Title,
    COALESCE(TRFQ2.FavoriteCount, 0) AS TopFavoritedQuestion2Faves,
    COALESCE(TRFQ3.Title, 'N/A') AS TopFavoritedQuestion3Title,
    COALESCE(TRFQ3.FavoriteCount, 0) AS TopFavoritedQuestion3Faves,
    -- Complicated expression: Hotness score for questions, involving division, logarithm, and date functions
    (PCM_Q.Score * 100.0 / NULLIF(PCM_Q.ViewCount, 0) + LOG(EXTRACT(EPOCH FROM (NOW() - PCM_Q.PostCreationDate)) / 3600.0)) AS QuestionHotnessMetric,
    COALESCE(DLA.DuplicateOfPostId, -1) AS LinkedDuplicatePostId, -- NULL logic, replacing NULL with -1
    DLA.DuplicatePostTitle,
    DLA.CloseReasonName,
    -- Correlated subquery for "highest reputation collaborator" on the specific question
    (
        SELECT MAX(U_COLLAB.Reputation)
        FROM Users U_COLLAB
        WHERE U_COLLAB.Id IN (
            SELECT C_COLLAB.UserId
            FROM Comments C_COLLAB
            WHERE C_COLLAB.PostId = PCM_Q.Id AND C_COLLAB.UserId IS NOT NULL AND C_COLLAB.UserId != HEU.UserId
            UNION -- Set operator: UNION for comments and answers
            SELECT P_COLLAB.OwnerUserId
            FROM Posts P_COLLAB
            WHERE P_COLLAB.ParentId = PCM_Q.Id AND P_COLLAB.PostTypeId = 2 AND P_COLLAB.OwnerUserId IS NOT NULL AND P_COLLAB.OwnerUserId != HEU.UserId
        )
    ) AS HighestCollabReputation,
    -- Date difference calculations
    EXTRACT(DAY FROM (NOW() - HEU.UserCreationDate)) AS DaysSinceUserCreation,
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
    -- String array and manipulation logic for cleaning and concatenating tags
    ARRAY_TO_STRING(
        ARRAY(
            SELECT UNNEST(string_to_array(SUBSTRING(PCM_Q.Tags FROM 2 FOR LENGTH(PCM_Q.Tags) - 2), '><')) -- SUBSTRING, LENGTH, string_to_array, UNNEST
            WHERE LENGTH(TRIM(UNNEST(string_to_array(SUBSTRING(PCM_Q.Tags FROM 2 FOR LENGTH(PCM_Q.Tags) - 2), '><')))) > 0 -- TRIM, LENGTH, and filtering
        ),
        ', '
    ) AS CleanedQuestionTags
FROM HighlyEngagedUsers HEU
JOIN PostComplexMetrics PCM_Q ON HEU.UserId = PCM_Q.OwnerUserId AND PCM_Q.PostTypeId = 1 -- Joining with complex post metrics for questions
LEFT JOIN RankedFavoriteQuestions TRFQ ON HEU.UserId = TRFQ.OwnerUserId AND TRFQ.RankNum = 1
LEFT JOIN RankedFavoriteQuestions TRFQ2 ON HEU.UserId = TRFQ2.OwnerUserId AND TRFQ2.RankNum = 2
LEFT JOIN RankedFavoriteQuestions TRFQ3 ON HEU.UserId = TRFQ3.OwnerUserId AND TRFQ3.RankNum = 3
LEFT JOIN DuplicateLinkAnalysis DLA ON PCM_Q.Id = DLA.OriginalPostId
WHERE
    PCM_Q.ViewCount > 1000 -- Additional filtering for "hot" questions
    AND (PCM_Q.WasClosed = 1 OR PCM_Q.EditCount > 5) -- Questions that were either closed or had significant edits
    AND PCM_Q.PostCreationDate > (NOW() - INTERVAL '3 years') -- Recent questions
ORDER BY
    HEU.Reputation DESC,
    PCM_Q.PostCreationDate DESC,
    QuestionHotnessMetric DESC
LIMIT 500;
