-- {"query": "1347.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3072} 

WITH OverallUserMetrics AS (
    -- Aggregates user-level metrics, including monthly activity summaries and initial vote counts.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(P.Score) AS TotalPostScore,
        SUM(P.ViewCount) AS TotalPostViews,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT DATE_TRUNC('month', P.CreationDate)) AS ActiveMonthsWithPosts,
        -- Correlated subquery to get total upvotes/downvotes given by the user
        (SELECT COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) FROM Votes AS V WHERE V.UserId = U.Id) AS TotalUpvotesGiven,
        (SELECT COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) FROM Votes AS V WHERE V.UserId = U.Id) AS TotalDownvotesGiven
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId AND P.CreationDate >= '2020-01-01' -- Filter recent posts
    LEFT JOIN Comments AS C ON U.Id = C.UserId AND C.CreationDate >= '2020-01-01' -- Filter recent comments
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING U.Reputation > 500
),
PostEngagementMetrics AS (
    -- Details for highly engaged questions and answers, including correlated subqueries for specific post types.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Title,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.Tags,
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        -- Correlated subquery for average comment score on this post
        (SELECT AVG(C.Score) FROM Comments AS C WHERE C.PostId = P.Id AND C.Score IS NOT NULL) AS AvgCommentScore,
        -- Correlated subquery for distinct editor count, focusing on content changes
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory AS PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6) AND PH.UserId IS NOT NULL) AS DistinctEditorCount
    FROM Posts AS P
    WHERE P.PostTypeId IN (1, 2) -- Only Questions and Answers
    AND P.CreationDate >= '2020-01-01'
    AND P.Score > 0
),
TagPerformance AS (
    -- Analyzes performance characteristics of specific tags.
    SELECT
        UPPER(TRIM(elem)) AS TagName,
        COUNT(DISTINCT PEM.PostId) AS QuestionsWithTag,
        AVG(PEM.PostScore) AS AvgScoreForTag,
        SUM(PEM.ViewCount) AS TotalViewsForTag,
        AVG(PEM.AnswerCount) AS AvgAnswersForTag,
        MAX(PEM.PostScore) AS MaxScoreForTag,
        COUNT(DISTINCT PEM.OwnerUserId) AS UniqueAuthorsForTag
    FROM PostEngagementMetrics AS PEM
    JOIN LATERAL unnest(string_to_array(substring(PEM.Tags, 2, length(PEM.Tags)-2), '><')) AS elem ON TRUE
    WHERE PEM.PostTypeId = 1 -- Only questions for tag performance
    AND PEM.Tags IS NOT NULL AND LENGTH(PEM.Tags) > 2
    GROUP BY UPPER(TRIM(elem))
    HAVING COUNT(DISTINCT PEM.PostId) > 50
),
BadgeAchievementRank AS (
    -- Ranks users based on their badge counts and types.
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        RANK() OVER (PARTITION BY B.Class ORDER BY COUNT(B.Id) DESC, B.UserId) AS RankByBadgeClass,
        NTILE(4) OVER (ORDER BY COUNT(B.Id) DESC) AS TotalBadgeQuartile -- NTILE window function
    FROM Badges AS B
    WHERE B.Date >= '2021-01-01'
    GROUP BY B.UserId
    HAVING COUNT(B.Id) > 5
),
PostHistoryDetails AS (
    -- Gathers detailed history about posts, including edit counts and close reasons.
    SELECT
        PH.PostId,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(PH.CreationDate) AS LastEditDate,
        MIN(PH.CreationDate) AS FirstEditDate,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 'Closed' ELSE NULL END) AS IsClosedFlag,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND CRT.Name IS NOT NULL THEN CRT.Name ELSE NULL END) AS LastCloseReason
    FROM PostHistory AS PH
    LEFT JOIN CloseReasonTypes AS CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment = CRT.Id::text -- Join for close reason names
    GROUP BY PH.PostId
),
DuplicatePostAnalysis AS (
    -- Identifies duplicate questions and provides comparative metrics.
    SELECT
        PL.PostId AS OriginalPostId,
        PL.RelatedPostId AS DuplicateOfPostId,
        PQ.Title AS OriginalTitle,
        DQ.Title AS DuplicateTitle,
        PQ.CreationDate AS OriginalCreationDate,
        DQ.CreationDate AS DuplicateCreationDate,
        COALESCE(PQ.Score, 0) AS OriginalScore,
        COALESCE(DQ.Score, 0) AS DuplicateScore,
        CASE
            WHEN PQ.CreationDate < DQ.CreationDate THEN 'Original_Older'
            WHEN PQ.CreationDate > DQ.CreationDate THEN 'Duplicate_Older'
            ELSE 'Same_Creation_Date'
        END AS CreationDateComparison
    FROM PostLinks AS PL
    JOIN Posts AS PQ ON PL.PostId = PQ.Id
    JOIN Posts AS DQ ON PL.RelatedPostId = DQ.Id
    WHERE PL.LinkTypeId = 3 AND PQ.PostTypeId = 1 AND DQ.PostTypeId = 1
),
HighlyEngagedOrClosedPosts AS (
    -- Uses UNION ALL to combine posts based on different criteria (closed or high comment count).
    SELECT PostId, 'ClosedPost' AS ReasonFlag, CreationDate, Score, CommentCount, LastActivityDate
    FROM Posts
    WHERE ClosedDate IS NOT NULL
      AND CreationDate >= '2021-01-01'
    UNION ALL
    SELECT PostId, 'HighCommentsPost' AS ReasonFlag, CreationDate, Score, CommentCount, LastActivityDate
    FROM Posts
    WHERE CommentCount > 50
      AND CreationDate >= '2021-01-01'
      AND PostTypeId = 1 -- Only questions for high comments criteria
)
SELECT
    OUM.UserId,
    OUM.DisplayName,
    OUM.Reputation,
    OUM.TotalPosts,
    OUM.TotalComments,
    OUM.ActiveMonthsWithPosts,
    OUM.TotalUpvotesGiven,
    OUM.TotalDownvotesGiven,
    COALESCE(BAR.GoldBadges, 0) AS GoldBadges,
    COALESCE(BAR.SilverBadges, 0) AS SilverBadges,
    COALESCE(BAR.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(BAR.TotalBadges, 0) AS TotalBadges,
    BAR.RankByBadgeClass,
    BAR.TotalBadgeQuartile,
    PEM.PostId AS TopQuestionId,
    PEM.Title AS TopQuestionTitle,
    PEM.PostScore AS TopQuestionScore,
    PEM.ViewCount AS TopQuestionViewCount,
    PEM.AnswerCount AS TopQuestionAnswerCount,
    PEM.HasAcceptedAnswer,
    COALESCE(PEM.AvgCommentScore, 0.0) AS TopQuestionAvgCommentScore,
    COALESCE(PEM.DistinctEditorCount, 0) AS TopQuestionDistinctEditorCount,
    COALESCE(T.TagName, 'Untagged') AS PrimaryTagOfTopQuestion,
    COALESCE(TP.AvgScoreForTag, 0.0) AS PrimaryTagAvgScore,
    COALESCE(TP.MaxScoreForTag, 0) AS PrimaryTagMaxScore,
    COALESCE(TP.UniqueAuthorsForTag, 0) AS PrimaryTagUniqueAuthors,
    COALESCE(PHD.EditCount, 0) AS QuestionEditCount,
    COALESCE(PHD.UniqueEditors, 0) AS QuestionUniqueEditors,
    PHD.LastCloseReason,
    AGE(NOW(), PHD.LastEditDate) AS TimeSinceLastEdit, -- Date difference calculation
    DPA.OriginalPostId AS PotentialDuplicateOriginalId,
    DPA.OriginalTitle AS PotentialDuplicateOriginalTitle,
    DPA.CreationDateComparison AS DuplicateCreationComparison,
    HEOC.ReasonFlag AS PostEngagementFlag,
    -- Complex weighted calculation for user influence, including NULL logic
    (
        (OUM.Reputation * 0.4) +
        (COALESCE(BAR.GoldBadges, 0) * 150.0) +
        (COALESCE(BAR.SilverBadges, 0) * 75.0) +
        (COALESCE(BAR.BronzeBadges, 0) * 25.0) +
        (COALESCE(OUM.TotalPostScore, 0) * 0.2) +
        (COALESCE(OUM.TotalPostViews, 0) * 0.005) -
        (COALESCE(OUM.TotalDownvotesGiven, 0) * 1.0)
    )::NUMERIC(18, 2) AS UserInfluenceScore,
    -- Elaborate string expression combining user and post data with formatting
    LOWER(
        SUBSTRING(OUM.DisplayName, 1, 5) ||
        '-' ||
        REPLACE(COALESCE(SUBSTRING(PEM.Title, 1, 20), 'NO_TITLE_DATA'), ' ', '_') ||
        '-PID:' ||
        TO_CHAR(PEM.PostId, 'FM000000000') ||
        '-CID:' ||
        TO_CHAR(COALESCE(PEM.OwnerUserId, -1), 'FM000000000')
    ) AS ComplexPostIdentifierHash
FROM OverallUserMetrics AS OUM
LEFT JOIN BadgeAchievementRank AS BAR ON OUM.UserId = BAR.UserId
LEFT JOIN PostEngagementMetrics AS PEM ON OUM.UserId = PEM.OwnerUserId AND PEM.PostTypeId = 1 AND PEM.PostScore = (
    -- Correlated subquery to find the highest-scoring question for each user
    SELECT MAX(P_inner.Score)
    FROM Posts AS P_inner
    WHERE P_inner.OwnerUserId = OUM.UserId
      AND P_inner.PostTypeId = 1
      AND P_inner.CreationDate >= '2020-01-01'
)
LEFT JOIN LATERAL (
    -- Lateral join to extract the first tag for the top question
    SELECT UPPER(TRIM(elem)) AS TagName
    FROM unnest(string_to_array(substring(PEM.Tags, 2, length(PEM.Tags)-2), '><')) AS elem
    WHERE PEM.Tags IS NOT NULL AND LENGTH(PEM.Tags) > 2
    LIMIT 1
) AS T ON TRUE
LEFT JOIN TagPerformance AS TP ON T.TagName = TP.TagName
LEFT JOIN PostHistoryDetails AS PHD ON PEM.PostId = PHD.PostId
LEFT JOIN DuplicatePostAnalysis AS DPA ON PEM.PostId = DPA.OriginalPostId
LEFT JOIN HighlyEngagedOrClosedPosts AS HEOC ON PEM.PostId = HEOC.PostId
WHERE OUM.ActiveMonthsWithPosts > 1 -- Ensure user has some sustained activity
  AND (PEM.PostId IS NULL OR PEM.ViewCount > 1000) -- Only include prominent posts or users with no prominent posts
  AND (BAR.TotalBadges IS NULL OR BAR.TotalBadges > 10 OR BAR.GoldBadges > 0) -- Filter for users with some badge achievements
ORDER BY
    UserInfluenceScore DESC,
    OUM.Reputation DESC,
    PEM.PostScore DESC NULLS LAST
LIMIT 1000;
