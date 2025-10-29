-- {"query": "1715.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3466} 

WITH UserEngagementSummary AS (
    -- CTE 1: Calculates various engagement metrics for users, including account age, post counts,
    -- total scores, and incorporates both correlated and non-correlated subqueries.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (60 * 60 * 24) AS AccountAgeDays,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        -- Correlated subquery: Calculates the average score of posts by this user that have been significantly edited at least twice.
        (
            SELECT AVG(P_sub.Score)
            FROM Posts P_sub
            WHERE P_sub.OwnerUserId = U.Id
            AND (SELECT COUNT(*) FROM PostHistory PH_sub WHERE PH_sub.PostId = P_sub.Id AND PH_sub.PostHistoryTypeId IN (4,5,6)) >= 2
        ) AS AvgScoreOfFrequentlyEditedPosts,
        -- Non-correlated subquery: Fetches the global average score for questions created in the last year.
        (
            SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate > NOW() - INTERVAL '1 year'
        ) AS GlobalAvgQuestionScoreLastYear
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Location
    HAVING
        COUNT(DISTINCT P.Id) > 5 -- Filters users with at least 5 posts.
        AND EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (60 * 60 * 24) > 365 -- Filters for accounts older than 1 year.
),
PostEditHistoryAgg AS (
    -- CTE 2: Aggregates post history data to determine edit counts, unique editors, and closure status.
    -- Also calculates the average time between major edits using a window function.
    SELECT
        PH.PostId,
        COUNT(DISTINCT CASE WHEN PH.UserId IS NOT NULL AND PH.UserId != P.OwnerUserId THEN PH.UserId END) AS UniqueEditorsCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS MajorEditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(PH.CreationDate) AS LastEditOrActivityDate,
        -- Window function: Calculates the average time in seconds between consecutive major edits for a post.
        AVG(EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))))
            FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6) AND LAG(PH.PostHistoryTypeId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) IN (4,5,6)) AS AvgTimeBetweenMajorEditsSeconds
    FROM
        PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id -- Join to get OwnerUserId for filtering editors.
    GROUP BY PH.PostId
),
TagAnalysis AS (
    -- CTE 3: Extracts individual tags from the 'Tags' string column, useful for tag-based analysis.
    -- Uses string functions `SUBSTRING`, `LENGTH`, `STRING_TO_ARRAY`, and `UNNEST`.
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName
    FROM
        Posts P
    WHERE
        P.Tags IS NOT NULL
        AND P.PostTypeId = 1 -- Focus on questions for tag analysis.
),
TagPerformanceMetrics AS (
    -- CTE 4: Aggregates performance metrics for each tag.
    -- Uses a window function to calculate a cumulative average score of alphabetically preceding tags.
    SELECT
        TA.TagName,
        COUNT(DISTINCT TA.PostId) AS TaggedQuestionCount,
        AVG(P.Score) AS AvgScoreForTag,
        -- Window function: Calculates the cumulative average score of all tags alphabetically preceding the current tag.
        AVG(AVG(P.Score)) OVER (ORDER BY TA.TagName ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS CumulativeAvgScorePrevTags
    FROM
        TagAnalysis TA
    JOIN Posts P ON TA.PostId = P.Id
    GROUP BY
        TA.TagName
    HAVING
        COUNT(DISTINCT TA.PostId) > 100 -- Filters for tags with at least 100 questions.
),
CombinedPostUserTagData AS (
    -- CTE 5: Integrates data from all previous CTEs and the Posts table.
    -- Calculates derived metrics like 'EngagementPerView' and 'ReputationPerPost'.
    -- Incorporates `DENSE_RANK` window function for post scoring.
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
        -- Window function: Ranks posts by score within their PostTypeId.
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS PostScoreRank,
        TPM.TagName AS RelatedTagName,
        TPM.AvgScoreForTag AS RelatedTagAvgScore,
        TPM.CumulativeAvgScorePrevTags,
        -- Complicated expression: Calculates an 'EngagementPerView' metric, handling potential division by zero with NULLIF.
        (CAST(P.Score + COALESCE(P.FavoriteCount, 0) * 2 + COALESCE(P.CommentCount, 0) * 0.5 AS NUMERIC) / NULLIF(P.ViewCount, 0)) AS EngagementPerView,
        -- Complicated expression: Calculates 'ReputationPerPost', handling potential division by zero with NULLIF.
        (CAST(UES.Reputation AS NUMERIC) / NULLIF(UES.TotalPosts, 0)) AS ReputationPerPost,
        -- String expression: Extracts the first tag from the Tags string, or 'Untagged' if none. Uses POSITION for string search.
        COALESCE(TRIM(SUBSTRING(P.Tags, 2, POSITION('>' IN P.Tags || '>') - 2)), 'Untagged') AS FirstTag,
        -- Calculates days to close for closed posts.
        EXTRACT(EPOCH FROM (PC.ClosedDate - P.CreationDate)) / (60 * 60 * 24) AS DaysToClose,
        CR.Name AS CloseReason
    FROM
        UserEngagementSummary UES
    JOIN Posts P ON UES.UserId = P.OwnerUserId
    LEFT JOIN PostEditHistoryAgg PEHA ON P.Id = PEHA.PostId
    LEFT JOIN TagAnalysis TA ON P.Id = TA.PostId
    LEFT JOIN TagPerformanceMetrics TPM ON TA.TagName = TPM.TagName
    LEFT JOIN Posts PC ON P.Id = PC.Id AND PC.ClosedDate IS NOT NULL -- Join to get ClosedDate for specific posts.
    LEFT JOIN PostHistory PH_Closed ON P.Id = PH_Closed.PostId AND PH_Closed.PostHistoryTypeId = 10 -- Link to PostHistory for closure event.
    LEFT JOIN CloseReasonTypes CR ON CAST(PH_Closed.Comment AS SMALLINT) = CR.Id -- Join to get actual CloseReasonName using CAST.
    WHERE
        P.PostTypeId = 1 -- Focus on Questions.
        AND P.ViewCount > 100 -- Only posts with a reasonable number of views.
        AND P.CreationDate > NOW() - INTERVAL '3 years' -- Relatively recent posts.
),
FinalAnalysisSet AS (
    -- CTE 6: Combines two distinct analytical scenarios using UNION ALL.
    -- Each scenario applies different complex filtering logic to highlight specific user/post characteristics.
    -- Scenario 1: Focuses on highly active users whose reputation might not fully reflect their engagement and who have posts with significant editing.
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
        -- String expression: Capitalizes the first letter of the title and lowercases the rest.
        UPPER(SUBSTRING(CPUT.Title, 1, 1)) || LOWER(SUBSTRING(CPUT.Title, 2, 50)) AS FormattedTitleSnippet,
        CPUT.DaysToClose,
        CPUT.CloseReason,
        'ActiveUserWithEditedPosts' AS AnalysisType
    FROM
        CombinedPostUserTagData CPUT
    WHERE
        CPUT.ReputationPerPost < 50 -- Reputation is low relative to posts.
        AND CPUT.EngagementPerView > 0.05 -- High engagement per view.
        AND CPUT.MajorEditCount > 3 -- Posts with significant edits.
        AND CPUT.PostScoreRank <= 100 -- Top posts by score.
        AND CPUT.WasClosed = 0 -- Not closed.
        AND CPUT.AvgTimeBetweenMajorEditsSeconds IS NOT NULL -- Requires at least two major edits.
        AND CPUT.AvgTimeBetweenMajorEditsSeconds < 86400 * 7 -- Edits happen relatively quickly (within a week).

    UNION ALL

    -- Scenario 2: Identifies recent posts from users with old accounts but historically low post counts,
    -- specifically focusing on posts with 'sql' or 'database' tags that perform better than their tag's average.
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
        CPUT.AccountAgeDays > 1000 -- Account is old (more than ~3 years).
        AND CPUT.TotalPosts < 20 -- But has few total posts.
        AND CPUT.PostCreationDate > NOW() - INTERVAL '6 months' -- Yet has a recent post.
        AND (CPUT.Tags ILIKE '%<sql>%' OR CPUT.Tags ILIKE '%<database>%') -- Specific technology tags.
        AND CPUT.WasClosed = 0 -- Not closed.
        AND CPUT.PostScore > COALESCE(CPUT.RelatedTagAvgScore, -1) -- Post performs better than average for its tag (handles NULL for AvgScore).
)
-- Final SELECT statement: Applies ultimate filtering, ordering, and additional window functions/calculations.
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
    -- Window function: Divides the result set for each analysis type into 5 groups (quintiles) based on engagement and reputation.
    NTILE(5) OVER (PARTITION BY FAS.AnalysisType ORDER BY FAS.EngagementPerView DESC, FAS.Reputation DESC) AS EngagementReputationQuintile,
    -- Complicated calculation with NULLIF and COALESCE: A weighted score combining engagement and reputation, defaulting to 0.0 if calculations result in NULL.
    COALESCE(FAS.EngagementPerView * NULLIF(FAS.ReputationPerPost, 0), 0.0) AS FinalWeightedScore
FROM
    FinalAnalysisSet FAS
WHERE
    FAS.PostScore IS NOT NULL AND FAS.PostScore > 0 -- Ensures positive score.
    AND FAS.EngagementPerView IS NOT NULL AND FAS.EngagementPerView > 0 -- Ensures positive engagement.
    AND (FAS.RelatedTagName IS NULL OR FAS.RelatedTagAvgScore IS NOT NULL) -- NULL logic: if a tag is present, its average score must be determinable.
ORDER BY
    FAS.AnalysisType DESC,
    EngagementReputationQuintile ASC,
    FAS.PostScore DESC,
    FAS.MajorEditCount DESC
LIMIT 500;
