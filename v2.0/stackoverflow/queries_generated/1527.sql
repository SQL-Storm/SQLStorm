-- {"query": "1527.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2739} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScoreAgg,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MIN(P.CreationDate) AS FirstPostDate,
        -- Correlated subquery: check if user has any gold badge (Class = 1)
        EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS HasGoldBadge,
        -- Conditional aggregation with NULL handling: count upvotes and downvotes given by the user
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesGiven,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.Tags,
        P.ParentId,
        -- String expression and NULL logic: extract first 100 chars of body, replace newlines, handle NULL
        LEFT(REPLACE(REPLACE(COALESCE(P.Body, ''), E'\r', ''), E'\n', ' '), 100) AS BodyPreview,
        -- Complicated calculation: engagement score (weighted sum, handles NULLs)
        (COALESCE(P.Score, 0) * 0.5) + (COALESCE(P.ViewCount, 0) * 0.05) + (COALESCE(P.CommentCount, 0) * 0.2) + (COALESCE(P.FavoriteCount, 0) * 0.25) AS EngagementScore,
        -- Window function: rank posts by score within each post type
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostTypeScoreRank,
        -- Window function: calculate average score for posts created in the same month
        AVG(P.Score) OVER (PARTITION BY DATE_TRUNC('month', P.CreationDate)) AS AvgMonthlyPostScore,
        -- Correlated subquery: count distinct editors for a post (PostHistoryTypeId 4, 5, 6 for edits)
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditorCount,
        -- NULL logic: check if post is community-owned or closed
        CASE WHEN P.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsCommunityOwned,
        CASE WHEN P.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsClosed
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.CreationDate >= '2020-01-01' -- Filter for recent data
),
PostTagsExpanded AS (
    -- Explode tags into individual rows for analysis
    SELECT
        PD.PostId,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM PD.Tags), '><')) AS TagName
    FROM PostDetails PD
    WHERE PD.Tags IS NOT NULL AND PD.PostTypeId = 1 -- Only consider tags on questions
),
AggregatedTagMetrics AS (
    SELECT
        PTE.TagName,
        COUNT(DISTINCT PTE.PostId) AS QuestionsWithTag,
        SUM(PD.Score) AS TotalTagScore,
        AVG(PD.EngagementScore) AS AvgTagEngagementScore,
        -- Window function: rank tags by total score
        DENSE_RANK() OVER (ORDER BY SUM(PD.Score) DESC, COUNT(DISTINCT PTE.PostId) DESC) AS TagScoreRank
    FROM PostTagsExpanded PTE
    JOIN PostDetails PD ON PTE.PostId = PD.PostId
    GROUP BY PTE.TagName
),
RecentAnswerActivity AS (
    SELECT
        P.ParentId AS QuestionId,
        COUNT(P.Id) AS RecentAnswerCount,
        SUM(P.Score) AS RecentAnswerScoreSum,
        MAX(P.CreationDate) AS LatestAnswerDate
    FROM Posts P
    WHERE P.PostTypeId = 2
    AND P.CreationDate >= '2023-01-01' -- Consider answers from last year for recency
    GROUP BY P.ParentId
),
QuestionClosureDetails AS (
    SELECT
        PH.PostId AS QuestionId,
        CRC.Name AS CloseReason,
        PH.CreationDate AS ClosureDate,
        -- String expression with regex for extracting specific JSON data for duplicates
        CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment LIKE '101' AND PH.Text IS NOT NULL THEN
            SUBSTRING(PH.Text FROM 'OriginalQuestionIds":\[(\d+(?:,\s*\d+)*)\]')
        ELSE NULL END AS DuplicateOriginalQuestionIds,
        -- Correlated subquery: check if the closure was initiated by a high-reputation user
        EXISTS (
            SELECT 1 FROM Users U_closer
            WHERE U_closer.Id = PH.UserId AND U_closer.Reputation > 10000
        ) AS ClosedByHighRepUser
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CRC ON CAST(PH.Comment AS SMALLINT) = CRC.Id
    WHERE PH.PostHistoryTypeId = 10 -- Post Closed
    AND PH.CreationDate >= '2022-01-01' -- Recent closures
),
TopPostsByYear AS (
    -- Set operator: Combine top questions and top answers by score for each year
    SELECT
        PD.PostId,
        PD.PostTypeName,
        PD.PostCreationDate,
        PD.Score,
        EXTRACT(YEAR FROM PD.PostCreationDate) AS PostYear,
        'TopQuestion' AS Category
    FROM PostDetails PD
    WHERE PD.PostTypeId = 1
    ORDER BY PD.Score DESC
    LIMIT 100 -- Top N questions overall for diversity
    UNION ALL
    SELECT
        PD.PostId,
        PD.PostTypeName,
        PD.PostCreationDate,
        PD.Score,
        EXTRACT(YEAR FROM PD.PostCreationDate) AS PostYear,
        'TopAnswer' AS Category
    FROM PostDetails PD
    WHERE PD.PostTypeId = 2
    ORDER BY PD.Score DESC
    LIMIT 100 -- Top N answers overall for diversity
)
-- Main Query combining all insights
SELECT
    UA.UserId,
    COALESCE(UA.DisplayName, 'Anonymous User') AS DisplayName,
    UA.Reputation,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    PD.PostId,
    COALESCE(PD.PostTypeName, 'N/A') AS PostTypeName,
    PD.PostCreationDate,
    PD.Score AS PostScore,
    PD.ViewCount,
    PD.FavoriteCount,
    PD.EngagementScore,
    PD.PostTypeScoreRank,
    PD.AvgMonthlyPostScore,
    COALESCE(PD.EditorCount, 0) AS EditorCount,
    PD.IsClosed,
    PD.IsCommunityOwned,
    COALESCE(QCD.CloseReason, 'Not Closed') AS LastCloseReason,
    QCD.ClosureDate,
    QCD.DuplicateOriginalQuestionIds,
    QCD.ClosedByHighRepUser,
    ATM.TagName AS PrimaryTag, -- Using first available tag for simplicity
    ATM.QuestionsWithTag,
    ATM.TotalTagScore,
    ATM.TagScoreRank,
    COALESCE(RAA.RecentAnswerCount, 0) AS RecentAnswersToQuestion,
    COALESCE(RAA.RecentAnswerScoreSum, 0) AS RecentAnswersTotalScore,
    RAA.LatestAnswerDate,
    TPBY.Category AS TopPostCategory,
    -- Complicated calculation with NULL logic: calculate 'active post life' in days
    EXTRACT(DAY FROM (COALESCE(PD.ClosedDate, PD.LastActivityDate, NOW()) - PD.PostCreationDate)) AS PostActiveDays,
    -- String expression: concatenate user and post info for an activity summary
    UA.DisplayName || ' (Rep: ' || UA.Reputation || ', Posts: ' || UA.TotalPosts || ') posted ' || PD.PostTypeName || ' "' || COALESCE(PD.BodyPreview, 'No Preview') || '" on ' || TO_CHAR(PD.PostCreationDate, 'YYYY-MM-DD') AS DetailedActivitySummary,
    -- Complex conditional expression based on various factors
    CASE
        WHEN PD.IsClosed AND COALESCE(RAA.RecentAnswerCount, 0) = 0 AND PD.PostTypeId = 1 THEN 'Closed Question, No Recent Engagement'
        WHEN PD.IsClosed AND COALESCE(RAA.RecentAnswerCount, 0) > 0 AND PD.PostTypeId = 1 THEN 'Closed Question, Still Receiving Answers'
        WHEN PD.EngagementScore > 100 AND COALESCE(PD.EditorCount, 0) > 1 THEN 'High Engagement & Collaborative Post'
        WHEN COALESCE(ATM.TagScoreRank, 999999) <= 10 THEN 'Question on Top-10 Trending Tag'
        WHEN UA.Reputation > 50000 AND UA.HasGoldBadge IS TRUE THEN 'Expert User High-Impact Post'
        ELSE 'General Community Activity'
    END AS PostEngagementCategory
FROM UserActivity UA
FULL OUTER JOIN PostDetails PD ON UA.UserId = PD.OwnerUserId
LEFT JOIN RecentAnswerActivity RAA ON PD.PostId = RAA.QuestionId AND PD.PostTypeId = 1 -- Answers relate to questions
LEFT JOIN QuestionClosureDetails QCD ON PD.PostId = QCD.QuestionId AND PD.PostTypeId = 1 -- Closures relate to questions
LEFT JOIN TopPostsByYear TPBY ON PD.PostId = TPBY.PostId
-- Join to AggregatedTagMetrics using EXISTS for tags that are part of a post
LEFT JOIN AggregatedTagMetrics ATM ON EXISTS (SELECT 1 FROM PostTagsExpanded PTE WHERE PTE.PostId = PD.PostId AND PTE.TagName = ATM.TagName)
WHERE
    (UA.UserId IS NOT NULL OR PD.PostId IS NOT NULL) -- Filter out rows that are entirely NULL from the FULL OUTER JOIN
AND
    (
        UA.HasGoldBadge IS TRUE
        OR UA.Reputation > 5000
        OR PD.EngagementScore > 50
        OR TPBY.PostId IS NOT NULL
    ) -- Filter for more interesting users/posts/data points
ORDER BY
    UA.Reputation DESC NULLS LAST,
    PD.EngagementScore DESC NULLS LAST,
    PD.PostCreationDate DESC
LIMIT 500;
