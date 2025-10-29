-- {"query": "1963.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3539} 

WITH UserSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.AnswerCount ELSE 0 END) AS TotalQuestionAnswerCount,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        (SELECT COUNT(C.Id) FROM Comments C WHERE C.UserId = U.Id) AS TotalCommentsMade, -- Correlated subquery
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId IN (2, 3)) AS TotalVotesCast, -- Correlated subquery
        MAX(P.CreationDate) AS LatestPostDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.OwnerUserId,
        P.LastEditDate,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.ClosedDate,
        COUNT(DISTINCT C.Id) AS TotalCommentsOnPost,
        COALESCE(AVG(C.Score), 0) AS AvgCommentScore,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        MAX(PH.CreationDate) AS LastHistoryEventDate,
        (SELECT PH_Inner.Text FROM PostHistory PH_Inner
         WHERE PH_Inner.PostId = P.Id AND PH_Inner.PostHistoryTypeId = 5 -- Edit Body
         ORDER BY PH_Inner.CreationDate DESC LIMIT 1) AS LastBodyEditContent, -- Correlated subquery for last body edit
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / 86400.0 AS PostAgeDays, -- Calculation for post age
        LENGTH(COALESCE(P.Body, '')) - LENGTH(REPLACE(COALESCE(P.Body, ''), ' ', '')) + 1 AS BodyWordCount, -- String expression and NULL logic
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(COALESCE(P.Tags, '<>'), 2, LENGTH(COALESCE(P.Tags, '<>')) - 2), '><'), 1) AS TagCount, -- String expression and NULL logic
        (
            SELECT MAX(CAST(PH_Close.Comment AS SMALLINT))
            FROM PostHistory PH_Close
            WHERE PH_Close.PostId = P.Id
            AND PH_Close.PostHistoryTypeId = 10 -- Post Closed
            AND PH_Close.Comment IS NOT NULL
            AND PH_Close.Comment ~ '^[0-9]+$' -- Ensure it's numeric
        ) AS LastCloseReasonTypeId, -- Correlated subquery for close reason
        SUM(CASE WHEN PH.PostHistoryTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS CumulativeInitialPosts, -- Window function
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScore -- Window function
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.LastEditDate, P.LastActivityDate, P.Title, P.Tags, P.CommentCount, P.FavoriteCount, P.ClosedDate
),
PostEventFlags AS (
    SELECT
        PH_Seq.PostId,
        MAX(CASE WHEN PH_Seq.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH_Seq.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH_Seq.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeleted,
        MAX(CASE WHEN PH_Seq.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS WasUndeleted,
        MAX(CASE WHEN PH_Seq.event_sequence = 'Closed -> Reopened' THEN 1 ELSE 0 END) AS ClosedThenReopened,
        MAX(CASE WHEN PH_Seq.event_sequence = 'Deleted -> Undeleted' THEN 1 ELSE 0 END) AS DeletedThenUndeleted
    FROM (
        SELECT
            PH.PostId,
            PH.PostHistoryTypeId,
            PH.CreationDate,
            LAG(PH.PostHistoryTypeId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevEventType,
            CASE
                WHEN PH.PostHistoryTypeId = 11 AND LAG(PH.PostHistoryTypeId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) = 10 THEN 'Closed -> Reopened'
                WHEN PH.PostHistoryTypeId = 13 AND LAG(PH.PostHistoryTypeId, 1) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) = 12 THEN 'Deleted -> Undeleted'
                ELSE NULL
            END AS event_sequence -- Window function for sequence detection
        FROM PostHistory PH
    ) AS PH_Seq
    GROUP BY PH_Seq.PostId
),
TagAnalysis AS (
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT T.Id) FILTER (WHERE T.TagName ILIKE '%sql%') AS HasSqlTag, -- String expression
        COUNT(DISTINCT T.Id) FILTER (WHERE T.TagName ILIKE '%performance%') AS HasPerformanceTag, -- String expression
        SUM(T.Count) AS SumOfAssociatedTagCounts,
        MAX(CASE WHEN T.IsModeratorOnly THEN 1 ELSE 0 END) AS HasModeratorOnlyTag
    FROM Posts P
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(COALESCE(P.Tags, '<>'), 2, LENGTH(COALESCE(P.Tags, '<>')) - 2), '><')) AS PostTag
    LEFT JOIN Tags T ON PostTag = T.TagName
    WHERE P.Tags IS NOT NULL AND LENGTH(TRIM(P.Tags)) > 2
    GROUP BY P.Id
),
SqlAnswerersWithoutSqlQuestions AS (
    SELECT DISTINCT P.OwnerUserId AS UserId
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    JOIN TagAnalysis TA ON P.Id = TA.PostId
    WHERE PT.Name = 'Answer' AND TA.HasSqlTag > 0
    EXCEPT -- Set operator
    SELECT DISTINCT P.OwnerUserId AS UserId
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    JOIN TagAnalysis TA ON P.Id = TA.PostId
    WHERE PT.Name = 'Question' AND TA.HasSqlTag > 0
),
FinalPostScores AS (
    SELECT
        PDM.PostId,
        PDM.OwnerUserId,
        PDM.PostTypeId,
        PDM.Title,
        PDM.PostCreationDate,
        PDM.PostScore,
        PDM.PostViewCount,
        PDM.PostAgeDays,
        PDM.BodyWordCount,
        PDM.AvgCommentScore,
        PDM.UniqueEditors,
        PDM.TagCount,
        COALESCE(PEF.WasClosed, 0) AS WasClosed,
        COALESCE(PEF.WasReopened, 0) AS WasReopened,
        COALESCE(PEF.ClosedThenReopened, 0) AS ClosedThenReopened,
        COALESCE(TA.HasSqlTag, 0) AS HasSqlTag,
        COALESCE(TA.HasPerformanceTag, 0) AS HasPerformanceTag,
        COALESCE(TA.SumOfAssociatedTagCounts, 0) AS SumOfAssociatedTagCounts,
        COALESCE(TA.HasModeratorOnlyTag, 0) AS HasModeratorOnlyTag,
        CASE
            WHEN PDM.PostScore > 100 AND PDM.ViewCount > 10000 THEN 'Very Popular'
            WHEN PDM.PostScore > 20 AND PDM.ViewCount > 1000 THEN 'Popular'
            WHEN PDM.PostScore > 0 AND PDM.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END AS PostPopularityLevel, -- Complicated expression with CASE
        -- Complex calculation using NULL logic and expressions
        (PDM.PostScore * 0.5) + (PDM.PostViewCount * 0.01) + (PDM.PostCommentCount * 0.2) +
        (COALESCE(PDM.PostFavoriteCount, 0) * 1.5) + (PDM.AvgCommentScore * 0.1) -
        (PDM.PostAgeDays * 0.001) + (COALESCE(PDM.TagCount, 0) * 0.05) + (PDM.UniqueEditors * 0.3) +
        (CASE WHEN COALESCE(PEF.ClosedThenReopened, 0) = 1 THEN -5.0 ELSE 0.0 END) + -- Penalty for closed/reopened posts
        (CASE WHEN PDM.Title ILIKE '%benchmark%' OR COALESCE(PDM.LastBodyEditContent, '') ILIKE '%performance%' THEN 2.5 ELSE 0.0 END) + -- Bonus for performance related content (string expression)
        (CASE WHEN PDM.PostTypeId = 1 AND PDM.LastCloseReasonTypeId = 101 THEN -3.0 ELSE 0.0 END) + -- Penalty for duplicate close reason
        (CASE WHEN PDM.PreviousPostScore IS NOT NULL AND PDM.PostScore > PDM.PreviousPostScore THEN 1.0 ELSE 0.0 END) -- Bonus if current post is better than previous
        AS CalculatedPostWeight
    FROM PostDetailedMetrics PDM
    LEFT JOIN PostEventFlags PEF ON PDM.PostId = PEF.PostId
    LEFT JOIN TagAnalysis TA ON PDM.PostId = TA.PostId
    WHERE
        PDM.OwnerUserId IS NOT NULL
        AND PDM.PostScore IS NOT NULL
        AND PDM.BodyWordCount > 50 -- Filter for substantial posts
        AND PDM.PostCreationDate BETWEEN '2020-01-01' AND '2023-12-31' -- Time-based filter
        AND (PDM.Title ILIKE '%sql%' OR COALESCE(PDM.LastBodyEditContent, '') ILIKE '%database%') -- String expression
)
-- Main query: Aggregate user scores and apply final filtering/ranking
SELECT
    US.UserId,
    US.DisplayName,
    US.Reputation,
    US.GoldBadges,
    US.SilverBadges,
    US.BronzeBadges,
    US.TotalPosts,
    US.TotalQuestions,
    US.TotalAnswers,
    SUM(FPS.CalculatedPostWeight) AS TotalWeightedPostScore,
    AVG(FPS.CalculatedPostWeight) AS AvgWeightedPostScore,
    MAX(US.LatestPostDate) AS LastUserActivity,
    COUNT(DISTINCT FPS.PostId) FILTER (WHERE FPS.HasSqlTag > 0 AND FPS.HasPerformanceTag > 0) AS RelevantPostsCount,
    -- Window function: Rank users by their total weighted post score
    RANK() OVER (ORDER BY SUM(FPS.CalculatedPostWeight) DESC, US.Reputation DESC) AS OverallInfluenceRank,
    -- Correlated Subquery: Check if user has posts with specific activity
    EXISTS (
        SELECT 1
        FROM PostHistory ph_check
        WHERE ph_check.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = US.UserId)
          AND ph_check.PostHistoryTypeId = 16 -- Community Owned
          AND ph_check.CreationDate > US.CreationDate
    ) AS HasCommunityOwnedPosts,
    (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = US.UserId AND V.VoteTypeId = 5) AS TotalFavoritesMade, -- Correlated subquery for favorite votes (bookmarks)
    NULLIF(US.TotalAnswers, 0) AS AnswerCountNullIfZero, -- NULL logic
    CASE
        WHEN US.Reputation > 10000 AND US.GoldBadges >= 5 THEN 'Guru'
        WHEN US.Reputation > 1000 AND US.SilverBadges >= 10 THEN 'Expert'
        ELSE 'Contributor'
    END AS UserLevel -- Complicated expression with CASE
FROM UserSummary US
JOIN FinalPostScores FPS ON US.UserId = FPS.OwnerUserId
WHERE
    US.TotalPosts > 5 -- Only consider users with a significant number of posts
    AND US.Reputation > 500
    AND (US.GoldBadges > 0 OR US.SilverBadges > 2)
    AND US.CreationDate < '2023-01-01' -- Filter for older users
    AND US.UserId NOT IN (SELECT UserId FROM SqlAnswerersWithoutSqlQuestions WHERE UserId IS NOT NULL) -- Set operator filter
    AND COALESCE(US.DisplayName, '') IS NOT NULL -- NULL logic
GROUP BY
    US.UserId, US.DisplayName, US.Reputation, US.GoldBadges, US.SilverBadges, US.BronzeBadges,
    US.TotalPosts, US.TotalQuestions, US.TotalAnswers, US.CreationDate
HAVING
    SUM(FPS.CalculatedPostWeight) > 50 -- Filter out users with low overall influence score
ORDER BY
    OverallInfluenceRank ASC, TotalWeightedPostScore DESC
LIMIT 100;
