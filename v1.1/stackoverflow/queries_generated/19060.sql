-- {"query": "19060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3028} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.PostId END) AS PostsEditedCount,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScoreReceived,
        AVG(EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate))/ (60*60*24.0)) AS AvgDaysActiveSinceCreation
    FROM
        Users U
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        PostHistory PH ON U.Id = PH.UserId AND PH.PostHistoryTypeId IN (4,5,6) -- Edit Title, Edit Body, Edit Tags
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
    HAVING
        U.Reputation > 1000 AND COUNT(DISTINCT B.Id) > 0 -- Users with some reputation and at least one badge
),
PostEngagementDetails AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.Tags,
        (SELECT MAX(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id) AS LatestCommentActivity,
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 5) AS UniqueFavoriters,
        COALESCE(P.AnswerCount, 0) AS ActualAnswerCount,
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / (60*60*24.0) AS DaysUntilLastActivity,
        COALESCE((SELECT SUM(CASE WHEN V.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) FROM Votes V WHERE V.PostId = P.Id), 0) AS TotalUpDownVotes,
        COALESCE((SELECT CAST(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS DECIMAL) / NULLIF(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) FROM Votes V WHERE V.PostId = P.Id), 0) AS UpvoteDownvoteRatio
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2) -- Questions or Answers
        AND P.CreationDate >= (NOW() - INTERVAL '3 year') -- Filter for recent posts to manage data size
),
TagPerformance AS (
    SELECT
        PE.PostId,
        PE.OwnerUserId,
        RANK() OVER (PARTITION BY PE.OwnerUserId, PE.PostTypeId ORDER BY PE.PostScore DESC, PE.ViewCount DESC) AS RankByScoreOwner,
        AVG(PE.PostScore) OVER (PARTITION BY PE.OwnerUserId, PE.PostTypeId ORDER BY PE.PostCreationDate ASC ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS OwnerPostTypeAvgScore3Posts,
        COALESCE(
            NULLIF(
                TRIM(SUBSTRING(PE.Tags FROM 2 FOR POSITION('><' IN PE.Tags) - 2)),
                ''
            ),
            'no-tag'
        ) AS PrimaryTag
    FROM
        PostEngagementDetails PE
    WHERE
        PE.Tags IS NOT NULL AND LENGTH(TRIM(PE.Tags)) > 2 -- Ensure tags exist and are not just '<>'
),
ClosedQuestionAnalysis AS (
    SELECT
        P.Id AS QuestionId,
        P.OwnerUserId,
        STRING_AGG(DISTINCT CRT.Name, ', ') AS AllCloseReasons,
        STRING_AGG(DISTINCT CAST(PL.RelatedPostId AS VARCHAR), ', ') AS DuplicateOfPostIds,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 11) AS ReopenAttempts,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$' THEN CAST(PH.Comment AS SMALLINT) ELSE NULL END) AS MainCloseReasonId,
        (
            SELECT MAX(PH_inner.CreationDate)
            FROM PostHistory PH_inner
            WHERE PH_inner.PostId = P.Id AND PH_inner.PostHistoryTypeId IN (10, 11)
        ) AS LatestCloseReopenEvent
    FROM
        Posts P
    JOIN
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN
        CloseReasonTypes CRT ON CAST(PH.Comment AS SMALLINT) = CRT.Id AND PH.PostHistoryTypeId = 10 AND PH.Comment ~ '^[0-9]+$'
    LEFT JOIN
        PostLinks PL ON P.Id = PL.PostId AND PL.LinkTypeId = 3 -- Duplicate links
    WHERE
        P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL AND PH.PostHistoryTypeId IN (10, 11)
    GROUP BY
        P.Id, P.OwnerUserId
)
-- Branch 1: Highly Engaged Posts from Reputable Users with specific tag interests
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalBadges,
    UAS.HasGoldBadge,
    PED.PostId,
    PED.PostTypeId,
    CASE
        WHEN PED.PostTypeId = 1 THEN 'Question'
        WHEN PED.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostTypeName,
    PED.Title,
    PED.PostScore,
    PED.ViewCount,
    PED.CommentCount,
    COALESCE(PED.FavoriteCount, 0) AS FavoriteCount,
    PED.LatestCommentActivity,
    PED.UniqueFavoriters,
    PED.ActualAnswerCount,
    TP.PrimaryTag,
    TP.RankByScoreOwner,
    TP.OwnerPostTypeAvgScore3Posts,
    NULL AS AllCloseReasons, -- NULL for this branch
    NULL AS DuplicateOfPostIds, -- NULL for this branch
    0 AS TotalReopenAttempts, -- 0 for this branch
    CAST(PED.TotalUpDownVotes AS DECIMAL) / NULLIF(PED.CommentCount + COALESCE(PED.FavoriteCount, 0) + 1, 0) AS ControversyScore,
    CASE
        WHEN PED.PostTypeId = 1 AND PED.ActualAnswerCount = 0 AND PED.CommentCount = 0 THEN 'Unanswered_Uncommented_Question'
        WHEN PED.DaysUntilLastActivity < 30 AND PED.PostScore > 50 THEN 'High_Impact_Recent'
        ELSE 'Active_Post'
    END AS PostStatusClassification,
    (PED.PostScore * 0.6 + PED.ViewCount * 0.005 + PED.CommentCount * 0.25 + COALESCE(PED.FavoriteCount, 0) * 0.2 + PED.UniqueFavoriters * 0.1) AS WeightedEngagementScore,
    T.Count AS PrimaryTagPostCount,
    T.IsModeratorOnly AS PrimaryTagModeratorOnly,
    LAG(PED.PostScore, 1, 0) OVER (PARTITION BY PED.OwnerUserId ORDER BY PED.PostCreationDate) AS PreviousPostScoreByOwner,
    LEAD(PED.PostCreationDate, 1) OVER (PARTITION BY PED.OwnerUserId ORDER BY PED.PostCreationDate) AS NextPostCreationDateByOwner,
    'Engaged_Post_Analysis' AS AnalysisType
FROM
    UserActivitySummary UAS
JOIN
    PostEngagementDetails PED ON UAS.UserId = PED.OwnerUserId
JOIN
    TagPerformance TP ON PED.PostId = TP.PostId AND PED.OwnerUserId = TP.OwnerUserId
LEFT JOIN
    Tags T ON TP.PrimaryTag = T.TagName
WHERE
    UAS.Reputation > 10000 -- Higher reputation threshold for this branch
    AND PED.PostScore > 10
    AND PED.ClosedDate IS NULL -- Only open posts
    AND PED.PostTypeId = 1 -- Only questions for this branch
    AND PED.ViewCount > 500
    AND PED.UpvoteDownvoteRatio > 2 -- Significantly more upvotes than downvotes
    AND TP.OwnerPostTypeAvgScore3Posts > 5
    AND (PED.Tags ILIKE '%<sql>%' OR PED.Tags ILIKE '%<database>%') -- Specific tags of interest
UNION ALL
-- Branch 2: Closed/Problematic Questions Analysis, potentially with reopen attempts or duplicates
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalBadges,
    UAS.HasGoldBadge,
    PED.PostId,
    PED.PostTypeId,
    CASE
        WHEN PED.PostTypeId = 1 THEN 'Question'
        WHEN PED.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostTypeName,
    PED.Title,
    PED.PostScore,
    PED.ViewCount,
    PED.CommentCount,
    COALESCE(PED.FavoriteCount, 0) AS FavoriteCount,
    PED.LatestCommentActivity,
    PED.UniqueFavoriters,
    PED.ActualAnswerCount,
    TP.PrimaryTag,
    TP.RankByScoreOwner,
    TP.OwnerPostTypeAvgScore3Posts,
    CQA.AllCloseReasons,
    CQA.DuplicateOfPostIds,
    COALESCE(CQA.ReopenAttempts, 0) AS TotalReopenAttempts,
    NULL AS ControversyScore, -- NULL for this branch
    CASE
        WHEN PED.ClosedDate IS NOT NULL AND COALESCE(CQA.ReopenAttempts, 0) > 0 THEN 'Closed_But_Reopened_Attempted'
        WHEN CQA.DuplicateOfPostIds IS NOT NULL THEN 'Closed_As_Duplicate'
        WHEN PED.ClosedDate IS NOT NULL AND PED.PostScore < 0 THEN 'Closed_Negative_Score'
        ELSE 'Closed_Other'
    END AS PostStatusClassification,
    (PED.PostScore * 0.1 - PED.CommentCount * 0.1 - COALESCE(PED.FavoriteCount, 0) * 0.05 + COALESCE(CQA.ReopenAttempts, 0) * 0.5) AS WeightedEngagementScore, -- Different calculation for problematic posts
    T.Count AS PrimaryTagPostCount,
    T.IsModeratorOnly AS PrimaryTagModeratorOnly,
    LAG(PED.PostScore, 1, 0) OVER (PARTITION BY PED.OwnerUserId ORDER BY PED.PostCreationDate) AS PreviousPostScoreByOwner,
    LEAD(PED.PostCreationDate, 1) OVER (PARTITION BY PED.OwnerUserId ORDER BY PED.PostCreationDate) AS NextPostCreationDateByOwner,
    'Closed_Post_Analysis' AS AnalysisType
FROM
    UserActivitySummary UAS
JOIN
    PostEngagementDetails PED ON UAS.UserId = PED.OwnerUserId
JOIN
    TagPerformance TP ON PED.PostId = TP.PostId AND PED.OwnerUserId = TP.OwnerUserId
JOIN
    ClosedQuestionAnalysis CQA ON PED.PostId = CQA.QuestionId -- INNER JOIN to focus only on closed questions
LEFT JOIN
    Tags T ON TP.PrimaryTag = T.TagName
WHERE
    UAS.Reputation > 2000 -- Lower reputation threshold for this branch
    AND PED.PostTypeId = 1 -- Only questions are closed
    AND PED.ClosedDate IS NOT NULL
    AND (COALESCE(CQA.ReopenAttempts, 0) > 0 OR CQA.DuplicateOfPostIds IS NOT NULL) -- Either reopened attempts or duplicates
    AND TP.OwnerPostTypeAvgScore3Posts < 10 -- Posts from users who might have lower average scores
ORDER BY
    AnalysisType ASC, WeightedEngagementScore DESC, Reputation DESC
LIMIT 2000;
