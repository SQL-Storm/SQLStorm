-- {"query": "1381.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3014} 

WITH UserContributionSummary AS (
    -- Calculate aggregated statistics for users regarding their posts and comments
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        AVG(COALESCE(P.Score, 0.0)) AS AveragePostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MIN(P.CreationDate) AS FirstPostDate,
        MAX(P.CreationDate) AS LastPostDate,
        DATE_PART('day', AGE(MAX(P.CreationDate), MIN(P.CreationDate))) AS DaysActiveInPosting,
        COUNT(DISTINCT PH.PostId) AS TotalPostsWithHistoryChanges,
        MAX(U.LastAccessDate) AS UserLastAccessDate
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId AND PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13) -- Edits, Close/Reopen, Delete/Undelete
    WHERE
        U.CreationDate >= '2020-01-01' -- Focus on more recent users
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.Views
),
PostVolatilityMetrics AS (
    -- Analyze post history to determine volatility and revision details
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS RevisionCount,
        COUNT(DISTINCT PH.UserId) AS DistinctEditorCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (11) THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (12) THEN 1 ELSE 0 END) AS WasDeleted,
        MAX(PH.CreationDate) AS LastRevisionDate,
        MIN(PH.CreationDate) AS FirstRevisionDate,
        -- Correlated subquery example: Get the latest closing reason if closed
        (
            SELECT CR.Name
            FROM PostHistory PH_INNER
            JOIN CloseReasonTypes CR ON CR.Id = CAST(PH_INNER.Comment AS smallint)
            WHERE PH_INNER.PostId = PH.PostId
              AND PH_INNER.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
            ORDER BY PH_INNER.CreationDate DESC
            LIMIT 1
        ) AS LatestCloseReasonName
    FROM
        PostHistory PH
    GROUP BY
        PH.PostId
    HAVING COUNT(PH.Id) > 1 -- Only consider posts with some history
),
TagPerformanceOverview AS (
    -- Analyze performance of tags associated with questions, including rank within tags
    SELECT
        P.Id AS PostId,
        P.Title,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS TagNameClean,
        T.Id AS TagId,
        T.Count AS TagGlobalCount,
        NTILE(5) OVER (PARTITION BY UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) ORDER BY P.Score DESC) AS TagScoreNtile,
        AVG(P.Score) OVER (PARTITION BY UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS AvgTagQuestionScore,
        COUNT(P.Id) OVER (PARTITION BY UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TotalTagQuestions
    FROM
        Posts P
    JOIN Tags T ON T.TagName = UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) -- Join tags for metadata
    WHERE
        P.PostTypeId = 1 -- Only questions
        AND P.Tags IS NOT NULL
        AND LENGTH(P.Tags) > 2 -- Ensure tags string is not empty or just "<>"
),
HighImpactAnswerers AS (
    -- Identify users who have a high proportion of accepted answers or high-scoring answers
    SELECT
        A.OwnerUserId AS UserId,
        COUNT(DISTINCT A.Id) AS TotalAnswers,
        SUM(CASE WHEN A.Id = Q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        SUM(A.Score) AS TotalAnswerScore,
        RANK() OVER (ORDER BY SUM(CASE WHEN A.Id = Q.AcceptedAnswerId THEN 1 ELSE 0 END) DESC, SUM(A.Score) DESC) AS AnswererRank
    FROM
        Posts A -- Answers
    JOIN Posts Q ON A.ParentId = Q.Id -- Questions linked to answers
    WHERE
        A.PostTypeId = 2 -- Only answers
        AND A.Score >= 5
    GROUP BY
        A.OwnerUserId
    HAVING SUM(CASE WHEN A.Id = Q.AcceptedAnswerId THEN 1 ELSE 0 END) >= 1
),
UserBadgeAchievements AS (
    -- Summarize user badge achievements, including class counts
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeAwardDate
    FROM
        Badges B
    GROUP BY
        B.UserId
),
TopQuestionContributors AS (
    -- First analytical path: Focus on top questioners and their questions' characteristics
    SELECT
        UCS.UserId,
        UCS.DisplayName,
        UCS.Reputation,
        'Question_Focus' AS AnalysisType,
        UCS.TotalQuestions,
        UCS.AveragePostScore,
        COALESCE(PV.LatestCloseReasonName, 'Open') AS QuestionCloseStatus,
        PV.RevisionCount,
        TPO.TagNameClean AS PrimaryQuestionTag,
        TPO.AvgTagQuestionScore,
        (
            SELECT MAX(V.BountyAmount)
            FROM Votes V
            WHERE V.PostId IN (SELECT P_Q.Id FROM Posts P_Q WHERE P_Q.OwnerUserId = UCS.UserId AND P_Q.PostTypeId = 1)
              AND V.VoteTypeId = 8 -- BountyStart
              AND V.BountyAmount IS NOT NULL
        ) AS MaxBountyOfferedByQuestioner, -- Correlated subquery for bounty
        RANK() OVER (ORDER BY UCS.TotalQuestions DESC, UCS.Reputation DESC) AS ContributorRank,
        LAG(UCS.DisplayName, 1, 'N/A') OVER (ORDER BY UCS.TotalQuestions DESC) AS PrevRankedContributor
    FROM
        UserContributionSummary UCS
    LEFT JOIN LATERAL (
        SELECT PV_INNER.*
        FROM Posts P_REP
        JOIN PostVolatilityMetrics PV_INNER ON P_REP.Id = PV_INNER.PostId
        WHERE P_REP.OwnerUserId = UCS.UserId AND P_REP.PostTypeId = 1 -- Only questions for volatility
        ORDER BY P_REP.Score DESC, P_REP.ViewCount DESC
        LIMIT 1
    ) PV ON TRUE
    LEFT JOIN LATERAL (
        SELECT TPO_INNER.*
        FROM TagPerformanceOverview TPO_INNER
        WHERE TPO_INNER.OwnerUserId = UCS.UserId AND TPO_INNER.PostId = PV.PostId -- Link tag to the representative question
        ORDER BY TPO_INNER.Score DESC -- Get the best performing tag for this specific question
        LIMIT 1
    ) TPO ON TRUE
    WHERE
        UCS.TotalQuestions > 10
        AND UCS.Reputation > 5000
        AND UCS.DisplayName IS NOT NULL AND UCS.DisplayName != ''
),
TopAnswerersAndBadgeHolders AS (
    -- Second analytical path: Focus on top answerers and badge holders
    SELECT
        UCS.UserId,
        UCS.DisplayName,
        UCS.Reputation,
        'Answer_Badge_Focus' AS AnalysisType,
        HIA.TotalAnswers,
        HIA.AcceptedAnswersCount,
        UBA.GoldBadges,
        UBA.SilverBadges,
        UBA.BronzeBadges,
        (HIA.AcceptedAnswersCount * 1.0 / NULLIF(HIA.TotalAnswers, 0)) AS AcceptedAnswerRatio, -- Calculation with NULLIF
        (
            SELECT P_ACC_ANS.Title
            FROM Posts P_ANS
            JOIN Posts P_ACC_ANS ON P_ANS.ParentId = P_ACC_ANS.Id
            WHERE P_ANS.OwnerUserId = UCS.UserId
              AND P_ANS.PostTypeId = 2
              AND P_ANS.Id = P_ACC_ANS.AcceptedAnswerId -- This answer was accepted
            ORDER BY P_ANS.Score DESC
            LIMIT 1
        ) AS TopAcceptedAnswerQuestionTitle, -- Correlated subquery for a top accepted answer's question title
        NTILE(4) OVER (ORDER BY HIA.AcceptedAnswersCount DESC, UBA.GoldBadges DESC) AS AnswererBadgeNtile,
        LEAD(UCS.DisplayName, 1, 'N/A') OVER (ORDER BY HIA.AcceptedAnswersCount DESC, UBA.GoldBadges DESC) AS NextRankedAnswerer
    FROM
        UserContributionSummary UCS
    JOIN HighImpactAnswerers HIA ON UCS.UserId = HIA.UserId -- INNER JOIN as we're focusing on impact answerers
    LEFT JOIN UserBadgeAchievements UBA ON UCS.UserId = UBA.UserId
    WHERE
        HIA.AcceptedAnswersCount >= 5
        AND UCS.Reputation > 7500
        AND COALESCE(UBA.GoldBadges, 0) >= 1 -- Only users with at least one gold badge, using COALESCE
        AND UCS.DisplayName IS NOT NULL AND UCS.DisplayName != ''
)
-- Final result: Combine both analytical paths using UNION ALL
SELECT
    UserId,
    DisplayName,
    Reputation,
    AnalysisType,
    TotalQuestions,
    TotalAnswers,
    AveragePostScore,
    NULL::int AS AcceptedAnswersCount, -- These columns are specific to one path, use NULL for the other with explicit type casts
    NULL::numeric AS AcceptedAnswerRatio,
    QuestionCloseStatus,
    RevisionCount,
    PrimaryQuestionTag,
    AvgTagQuestionScore,
    MaxBountyOfferedByQuestioner,
    ContributorRank AS CombinedRank,
    PrevRankedContributor AS PeerContributor,
    NULL::int AS GoldBadges,
    NULL::int AS SilverBadges,
    NULL::int AS BronzeBadges,
    NULL::varchar(300) AS TopAcceptedAnswerQuestionTitle,
    NULLIF(DisplayName, 'Community') AS ActualDisplayNameIfNoCommunity
FROM TopQuestionContributors
WHERE ContributorRank <= 50 -- Limit to top N questioners

UNION ALL

SELECT
    UserId,
    DisplayName,
    Reputation,
    AnalysisType,
    NULL::int AS TotalQuestions,
    TotalAnswers,
    NULL::numeric AS AveragePostScore,
    AcceptedAnswersCount,
    AcceptedAnswerRatio,
    NULL::varchar(50) AS QuestionCloseStatus,
    NULL::bigint AS RevisionCount,
    NULL::varchar(255) AS PrimaryQuestionTag,
    NULL::numeric AS AvgTagQuestionScore,
    NULL::int AS MaxBountyOfferedByQuestioner,
    AnswererBadgeNtile AS CombinedRank, -- Using NTILE as rank here, could be RANK too
    NextRankedAnswerer AS PeerContributor,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TopAcceptedAnswerQuestionTitle,
    NULLIF(DisplayName, 'Community') AS ActualDisplayNameIfNoCommunity
FROM TopAnswerersAndBadgeHolders
WHERE AnswererBadgeNtile <= 2 -- Limit to top 2 NTILE groups for answerers and badge holders

ORDER BY Reputation DESC, CombinedRank ASC
LIMIT 100;
