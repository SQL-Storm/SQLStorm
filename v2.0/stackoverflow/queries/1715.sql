-- {"query": "1715.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3466}
WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) / (60 * 60 * 24) AS AccountAgeDays,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        (
            SELECT AVG(P_sub.Score)
            FROM Posts P_sub
            WHERE P_sub.OwnerUserId = U.Id
            AND (SELECT COUNT(*) FROM PostHistory PH_sub WHERE PH_sub.PostId = P_sub.Id AND PH_sub.PostHistoryTypeId IN (4,5,6)) >= 2
        ) AS AvgScoreOfFrequentlyEditedPosts,
        (
            SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
        ) AS GlobalAvgQuestionScoreLastYear
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Location
    HAVING
        COUNT(DISTINCT P.Id) > 5
        AND EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) / (60 * 60 * 24) > 365
),
PostEditHistoryAgg AS (
    -- Compute LAG in a subquery, then aggregate without using FILTER on window functions
    SELECT
        t.PostId,
        COUNT(DISTINCT CASE WHEN t.UserId IS NOT NULL AND t.UserId != t.OwnerUserId THEN t.UserId END) AS UniqueEditorsCount,
        SUM(CASE WHEN t.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEditCount,
        MAX(CASE WHEN t.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(t.CreationDate) AS LastEditOrActivityDate,
        AVG(NULLIF(t.SecondsSincePrev, 0)) AS AvgTimeBetweenMajorEditsSeconds
    FROM (
        SELECT
            PH.PostId,
            PH.UserId,
            P.OwnerUserId,
            PH.PostHistoryTypeId,
            PH.CreationDate,
            EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) AS SecondsSincePrev,
            LAG(PH.PostHistoryTypeId) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevType
        FROM PostHistory PH
        JOIN Posts P ON PH.PostId = P.Id
    ) t
    WHERE
        -- keep only intervals where both current and previous are major edits
        (t.PostHistoryTypeId IN (4,5,6) AND t.PrevType IN (4,5,6))
        OR 1=1 -- keep all rows for counts/flags; the AVG uses SecondsSincePrev which is NULL except when condition above true
    GROUP BY t.PostId
),
TagAnalysis AS (
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName
    FROM
        Posts P
    WHERE
        P.Tags IS NOT NULL
        AND P.PostTypeId = 1
),
TagPerformanceMetrics AS (
    SELECT
        TA.TagName,
        COUNT(DISTINCT TA.PostId) AS TaggedQuestionCount,
        AVG(P.Score) AS AvgScoreForTag,
        AVG(AVG(P.Score)) OVER (ORDER BY TA.TagName ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS CumulativeAvgScorePrevTags
    FROM
        TagAnalysis TA
    JOIN Posts P ON TA.PostId = P.Id
    GROUP BY
        TA.TagName
    HAVING
        COUNT(DISTINCT TA.PostId) > 100
),
CombinedPostUserTagData AS (
    SELECT
        UES.UserId,
        UES.DisplayName,
        UES.Reputation,
        UES.AccountAgeDays,
        UES.TotalPosts,
        UES.TotalQuestions,
        UES.TotalAnswers,
        UES.TotalComments,
        UES.AvgScoreOfFrequentlyEditedPosts,
        P.Id AS PostId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Tags,
        P.PostTypeId,
        PEHA.MajorEditCount,
        PEHA.UniqueEditorsCount,
        PEHA.WasClosed,
        PEHA.AvgTimeBetweenMajorEditsSeconds,
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS PostScoreRank,
        TPM.TagName AS RelatedTagName,
        TPM.AvgScoreForTag AS RelatedTagAvgScore,
        TPM.CumulativeAvgScorePrevTags,
        (CAST(P.Score + COALESCE(P.FavoriteCount, 0) * 2 + COALESCE(P.CommentCount, 0) * 0.5 AS NUMERIC) / NULLIF(P.ViewCount, 0)) AS EngagementPerView,
        (CAST(UES.Reputation AS NUMERIC) / NULLIF(UES.TotalPosts, 0)) AS ReputationPerPost,
        COALESCE(TRIM(SUBSTRING(P.Tags, 2, POSITION('>' IN P.Tags || '>') - 2)), 'Untagged') AS FirstTag,
        EXTRACT(EPOCH FROM (PC.ClosedDate - P.CreationDate)) / (60 * 60 * 24) AS DaysToClose,
        CR.Name AS CloseReason
    FROM
        UserEngagementSummary UES
    JOIN Posts P ON UES.UserId = P.OwnerUserId
    LEFT JOIN PostEditHistoryAgg PEHA ON P.Id = PEHA.PostId
    LEFT JOIN TagAnalysis TA ON P.Id = TA.PostId
    LEFT JOIN TagPerformanceMetrics TPM ON TA.TagName = TPM.TagName
    LEFT JOIN Posts PC ON P.Id = PC.Id AND PC.ClosedDate IS NOT NULL
    LEFT JOIN PostHistory PH_Closed ON P.Id = PH_Closed.PostId AND PH_Closed.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes CR ON CAST(PH_Closed.Comment AS SMALLINT) = CR.Id
    WHERE
        P.PostTypeId = 1
        AND P.ViewCount > 100
        AND P.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years'
),
FinalAnalysisSet AS (
    SELECT
        CPUT.DisplayName,
        CPUT.Reputation,
        CPUT.AccountAgeDays,
        CPUT.TotalPosts,
        CPUT.PostId,
        CPUT.Title,
        CPUT.PostScore,
        CPUT.MajorEditCount,
        CPUT.UniqueEditorsCount,
        CPUT.EngagementPerView,
        CPUT.ReputationPerPost,
        CPUT.FirstTag,
        CPUT.RelatedTagName,
        CPUT.RelatedTagAvgScore,
        UPPER(SUBSTRING(CPUT.Title, 1, 1)) || LOWER(SUBSTRING(CPUT.Title, 2, 50)) AS FormattedTitleSnippet,
        CPUT.DaysToClose,
        CPUT.CloseReason,
        'ActiveUserWithEditedPosts' AS AnalysisType
    FROM
        CombinedPostUserTagData CPUT
    WHERE
        CPUT.ReputationPerPost < 50
        AND CPUT.EngagementPerView > 0.05
        AND CPUT.MajorEditCount > 3
        AND CPUT.PostScoreRank <= 100
        AND CPUT.WasClosed = 0
        AND CPUT.AvgTimeBetweenMajorEditsSeconds IS NOT NULL
        AND CPUT.AvgTimeBetweenMajorEditsSeconds < 86400 * 7

    UNION ALL

    SELECT
        CPUT.DisplayName,
        CPUT.Reputation,
        CPUT.AccountAgeDays,
        CPUT.TotalPosts,
        CPUT.PostId,
        CPUT.Title,
        CPUT.PostScore,
        CPUT.MajorEditCount,
        CPUT.UniqueEditorsCount,
        CPUT.EngagementPerView,
        CPUT.ReputationPerPost,
        CPUT.FirstTag,
        CPUT.RelatedTagName,
        CPUT.RelatedTagAvgScore,
        UPPER(SUBSTRING(CPUT.Title, 1, 1)) || LOWER(SUBSTRING(CPUT.Title, 2, 50)) AS FormattedTitleSnippet,
        CPUT.DaysToClose,
        CPUT.CloseReason,
        'OldAccountSparseRecentPosts' AS AnalysisType
    FROM
        CombinedPostUserTagData CPUT
    WHERE
        CPUT.AccountAgeDays > 1000
        AND CPUT.TotalPosts < 20
        AND CPUT.PostCreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
        AND (CPUT.Tags ILIKE '%<sql>%' OR CPUT.Tags ILIKE '%<database>%')
        AND CPUT.WasClosed = 0
        AND CPUT.PostScore > COALESCE(CPUT.RelatedTagAvgScore, -1)
)
SELECT
    FAS.DisplayName,
    FAS.Reputation,
    FAS.AccountAgeDays,
    FAS.TotalPosts,
    FAS.PostId,
    FAS.Title,
    FAS.FormattedTitleSnippet,
    FAS.PostScore,
    FAS.MajorEditCount,
    FAS.UniqueEditorsCount,
    FAS.EngagementPerView,
    FAS.ReputationPerPost,
    FAS.FirstTag,
    FAS.RelatedTagName,
    FAS.RelatedTagAvgScore,
    FAS.AnalysisType,
    FAS.DaysToClose,
    FAS.CloseReason,
    NTILE(5) OVER (PARTITION BY FAS.AnalysisType ORDER BY FAS.EngagementPerView DESC, FAS.Reputation DESC) AS EngagementReputationQuintile,
    COALESCE(FAS.EngagementPerView * NULLIF(FAS.ReputationPerPost, 0), 0.0) AS FinalWeightedScore
FROM
    FinalAnalysisSet FAS
WHERE
    FAS.PostScore IS NOT NULL AND FAS.PostScore > 0
    AND FAS.EngagementPerView IS NOT NULL AND FAS.EngagementPerView > 0
    AND (FAS.RelatedTagName IS NULL OR FAS.RelatedTagAvgScore IS NOT NULL)
ORDER BY
    FAS.AnalysisType DESC,
    EngagementReputationQuintile ASC,
    FAS.PostScore DESC,
    FAS.MajorEditCount DESC
LIMIT 500;