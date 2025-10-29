-- {"query": "1620.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3201}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        MAX(P.CreationDate) AS LatestPostDate,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(P.ViewCount, 0)) AS AveragePostViewCount,
        CASE
            WHEN U.Reputation >= 10000 AND COUNT(DISTINCT P.Id) >= 100 THEN 'Legendary'
            WHEN U.Reputation >= 5000 AND COUNT(DISTINCT P.Id) >= 50 THEN 'Expert'
            WHEN U.Reputation >= 1000 AND COUNT(DISTINCT P.Id) >= 10 THEN 'Contributor'
            ELSE 'Novice'
        END AS UserTier,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM U.CreationDate) ORDER BY U.Reputation DESC, U.Id ASC) AS ReputationRankInYear
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.LastActivityDate,
        P.LastEditorUserId,
        P.Tags,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        (COALESCE(P.Score, 0) * 2) + COALESCE(P.CommentCount, 0) + (COALESCE(P.FavoriteCount, 0) * 3) AS ActivityScore,
        CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - P.LastActivityDate)) / 86400 AS DaysSinceLastActivity,
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND POSITION('>' IN SUBSTRING(P.Tags FROM 2)) > 1
            THEN SUBSTRING(P.Tags FROM 2 FOR POSITION('>' IN SUBSTRING(P.Tags FROM 2)) - 1)
            ELSE NULL
        END AS FirstTag,
        COALESCE(
            CASE
                WHEN P.Tags IS NOT NULL THEN
                    (
                        SELECT COUNT(*) FROM (
                            SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS t
                        ) s
                    )
                ELSE 0
            END, 0) AS TagCount
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2)
        AND P.CreationDate >= DATE '2020-01-01'
),
LatestPostEditHistory AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS LastEditHistoryDate,
        PH.UserId AS LastEditorHistoryUserId,
        PHT.Name AS LastHistoryTypeName,
        PH.Comment AS LastHistoryComment,
        CASE
            WHEN PH.PostHistoryTypeId IN (7, 8, 9, 12, 10) THEN TRUE
            ELSE FALSE
        END AS WasCriticalHistoryAction,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC, PH.Id DESC) AS rn
    FROM
        PostHistory PH
    JOIN
        PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE
        PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
),
AnswerAggregates AS (
    SELECT
        P.ParentId AS QuestionId,
        COUNT(P.Id) AS TotalAnswersToQuestion,
        SUM(COALESCE(P.Score, 0)) AS TotalAnswerScoreForQuestion,
        AVG(COALESCE(P.Score, 0)) AS AvgAnswerScoreForQuestion,
        MAX(P.CreationDate) AS LatestAnswerDateForQuestion
    FROM
        Posts P
    WHERE
        P.PostTypeId = 2
    GROUP BY
        P.ParentId
),
BadgesPerUser AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.TagBased = TRUE THEN B.Id END) AS TagBasedBadges
    FROM Badges B
    GROUP BY B.UserId
)
SELECT
    UE.DisplayName AS User_DisplayName,
    UE.Reputation AS User_Reputation,
    UE.UserTier AS User_ReputationTier,
    UE.ReputationRankInYear AS User_ReputationRankInCreationYear,
    COALESCE(BP.TotalBadges, 0) AS User_TotalBadges,
    COALESCE(BP.GoldBadges, 0) AS User_GoldBadges,
    COALESCE(BP.SilverBadges, 0) AS User_SilverBadges,
    PD.Title AS Post_Title,
    PD.PostId AS Post_Id,
    PT.Name AS Post_TypeName,
    PD.CreationDate AS Post_CreationDate,
    PD.Score AS Post_Score,
    PD.ViewCount AS Post_ViewCount,
    PD.ActivityScore AS Post_CalculatedActivityScore,
    PD.HasAcceptedAnswer AS Post_HasAcceptedAnswer,
    PD.DaysSinceLastActivity AS Post_DaysSinceLastActivity,
    PD.FirstTag AS Post_MainTag,
    PD.TagCount AS Post_TagCount,
    LPEH.LastEditHistoryDate AS Post_LastEditOrHistoryDate,
    LPEH.LastHistoryTypeName AS Post_LastHistoryType,
    LPEH.WasCriticalHistoryAction AS Post_HadCriticalCriticalHistoryAction,
    AA.TotalAnswersToQuestion AS Question_TotalAnswers,
    AA.AvgAnswerScoreForQuestion AS Question_AverageAnswerScore,
    (
        SELECT
            C.Text
        FROM
            Comments C
        WHERE
            C.PostId = PD.PostId
        ORDER BY
            C.Score DESC, C.CreationDate DESC
        LIMIT 1
    ) AS TopCommentText,
    AVG(PD.Score) OVER (PARTITION BY UE.UserId, EXTRACT(MONTH FROM PD.CreationDate)) AS AvgMonthlyUserPostScore,
    COALESCE(
        (SELECT U2.DisplayName FROM Users U2 WHERE U2.Id = PD.LastEditorUserId),
        'N/A - Original Post / No Editor'
    ) AS Post_LastEditorDisplayName,
    CASE
        WHEN
            PD.PostTypeId = 1
            AND (LOWER(PD.Title) LIKE '%performance%' OR LOWER(PD.Title) LIKE '%optimization%')
            AND (PD.FirstTag IN ('sql', 'postgresql', 'mysql', 'database') OR PD.Tags LIKE '%<benchmark>%')
            AND UE.UserTier IN ('Expert', 'Legendary')
            AND PD.ActivityScore >= 20
            AND PD.DaysSinceLastActivity <= 60
            AND PD.HasAcceptedAnswer IS TRUE
            AND COALESCE(AA.TotalAnswersToQuestion, 0) > 1
        THEN 'HighValuePerformanceQuestion'
        WHEN
            PD.PostTypeId = 2
            AND PD.Score >= 10
            AND PD.DaysSinceLastActivity <= 45
            AND UE.UserTier IN ('Expert', 'Legendary', 'Contributor')
            AND (LPEH.WasCriticalHistoryAction IS FALSE OR LPEH.WasCriticalHistoryAction IS NULL)
            AND PD.OwnerUserId = LPEH.LastEditorHistoryUserId
            AND EXISTS (SELECT 1 FROM Comments C WHERE C.PostId = PD.PostId AND C.CreationDate > PD.CreationDate - INTERVAL '7 days' AND C.Score >= 1)
        THEN 'TopTierRecentAnswer'
        WHEN
            PD.PostTypeId = 1
            AND PD.Title IS NOT NULL
            AND PD.Score > 0
            AND PD.ViewCount > 500
            AND PD.TagCount >= 3
            AND (COALESCE(AA.TotalAnswersToQuestion, 0) = 0 OR AA.TotalAnswersToQuestion < 5)
            AND PD.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
            AND PD.ClosedDate IS NULL
            AND NOT EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = PD.PostId AND PL.LinkTypeId = 3)
        THEN 'NewPromisingQuestion'
        ELSE 'GeneralPost'
    END AS Post_Classification,
    (
        SELECT
            STRING_AGG(tn, ', ')
        FROM (
            SELECT T.TagName AS tn, COUNT(*) AS cnt
            FROM Tags T
            WHERE PD.Tags IS NOT NULL AND PD.Tags LIKE ('%' || '<' || T.TagName || '>' || '%')
            GROUP BY T.TagName
            ORDER BY cnt DESC
            LIMIT 3
        ) sub
    ) AS Top3RelatedTags
FROM
    UserEngagement UE
JOIN
    PostDetails PD ON UE.UserId = PD.OwnerUserId
JOIN
    PostTypes PT ON PD.PostTypeId = PT.Id
LEFT JOIN
    LatestPostEditHistory LPEH ON PD.PostId = LPEH.PostId AND LPEH.rn = 1
LEFT JOIN
    AnswerAggregates AA ON PD.PostId = AA.QuestionId AND PD.PostTypeId = 1
LEFT JOIN
    BadgesPerUser BP ON UE.UserId = BP.UserId
WHERE
    PD.CreationDate >= DATE '2020-01-01'
    AND PD.LastActivityDate IS NOT NULL
    AND PD.PostTypeId IN (1, 2)
    AND (
        (
            PD.PostTypeId = 1
            AND PD.HasAcceptedAnswer IS TRUE
            AND COALESCE(AA.TotalAnswersToQuestion, 0) > 0
            AND PD.ActivityScore >= 15
            AND UE.UserTier IN ('Expert', 'Legendary')
            AND (LPEH.WasCriticalHistoryAction IS FALSE OR LPEH.WasCriticalHistoryAction IS NULL)
            AND LPEH.LastEditHistoryDate IS NOT NULL
            AND EXISTS (
                SELECT 1
                FROM Comments C
                WHERE C.PostId = PD.PostId
                AND C.Score > 0
                AND C.CreationDate > PD.CreationDate - INTERVAL '90 days'
            )
        )
        OR
        (
            PD.PostTypeId = 2
            AND PD.Score >= 5
            AND PD.DaysSinceLastActivity <= 60
            AND UE.UserTier IN ('Contributor', 'Expert', 'Legendary')
            AND COALESCE(BP.SilverBadges, 0) >= 1
            AND NOT EXISTS (
                SELECT 1 FROM Votes V WHERE V.PostId = PD.PostId AND V.VoteTypeId = 4
            )
        )
        OR
        (
            PD.PostTypeId = 1
            AND PD.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
            AND PD.ViewCount > 1000
            AND PD.Score > 0
            AND PD.TagCount >= 2
            AND (LOWER(PD.Title) LIKE '%api%' OR LOWER(PD.FirstTag) = 'api')
            AND PD.ClosedDate IS NULL
            AND (COALESCE(AA.TotalAnswersToQuestion, 0) = 0 OR AA.TotalAnswersToQuestion < 5)
        )
    )
ORDER BY
    UE.Reputation DESC, PD.ActivityScore DESC, PD.CreationDate DESC
LIMIT 1000;