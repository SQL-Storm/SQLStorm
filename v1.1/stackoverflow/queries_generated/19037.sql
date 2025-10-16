-- {"query": "19037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3519} 

WITH UserEngagementStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPostsByOwner,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsByOwner,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersByOwner,
        COUNT(DISTINCT C.Id) AS TotalCommentsByOwner,
        AVG(P.Score) AS AvgPostScoreByOwner,
        MAX(P.LastActivityDate) AS LastPostActivityByOwner,
        MAX(C.CreationDate) AS LastCommentActivityByOwner,
        -- Correlated subquery: Get the latest gold badge date for a user
        (SELECT MAX(B.Date) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS LastGoldBadgeDate,
        -- Conditional calculation based on reputation
        CASE
            WHEN U.Reputation >= 10000 THEN 'Legendary'
            WHEN U.Reputation >= 5000 THEN 'Expert'
            WHEN U.Reputation >= 1000 THEN 'Advanced'
            WHEN U.Reputation >= 200 THEN 'Journeyman'
            ELSE 'Novice'
        END AS ReputationTier
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.ParentId,
        P.AcceptedAnswerId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.Body,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        LENGTH(P.Body) AS BodyLength,
        COALESCE(P.OwnerDisplayName, 'Community User') AS EffectiveOwnerDisplayName,
        -- String expression and NULL logic for tags
        NULLIF(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '') AS TagsCleaned,
        -- Calculate age of post in hours
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / 3600 AS PostAgeInHours,
        -- Correlated subquery to check if this post has been edited by a user with > 5000 reputation
        EXISTS (
            SELECT 1 FROM PostHistory PH_corr
            WHERE PH_corr.PostId = P.Id
              AND PH_corr.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
              AND PH_corr.UserId IS NOT NULL
              AND (SELECT U_corr.Reputation FROM Users U_corr WHERE U_corr.Id = PH_corr.UserId) > 5000
        ) AS EditedByHighRepUser
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
),
LatestPostHistory AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate ELSE NULL END) AS LastEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS ClosedHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate ELSE NULL END) AS ReopenedHistoryDate,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE NULL END) AS TotalEditCount,
        -- Aggregate text field for closure reasons, handling NULLs and non-existent reasons
        COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END), 'Not Closed') AS ClosureReasonComment
    FROM PostHistory PH
    GROUP BY PH.PostId
),
CommentEngagement AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalPostComments,
        AVG(C.Score) AS AverageCommentScore,
        MAX(C.CreationDate) AS LatestCommentDate,
        -- Non-correlated subquery: Find the second highest scored comment's text for each post
        (SELECT Text FROM Comments C_inner WHERE C_inner.PostId = C.PostId ORDER BY Score DESC, CreationDate DESC LIMIT 1 OFFSET 1) AS SecondHighestCommentText
    FROM Comments C
    GROUP BY C.PostId
),
PostLinkSummary AS (
    SELECT
        PL.PostId,
        COUNT(CASE WHEN LT.Name = 'Linked' THEN 1 ELSE NULL END) AS LinkedCount,
        COUNT(CASE WHEN LT.Name = 'Duplicate' THEN 1 ELSE NULL END) AS DuplicateCount
    FROM PostLinks PL
    JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    GROUP BY PL.PostId
),
BaseQuery AS (
    SELECT
        PDE.PostId,
        PDE.PostTypeName,
        PDE.Title,
        PDE.PostScore,
        PDE.ViewCount,
        PDE.CommentCount,
        PDE.FavoriteCount,
        PDE.OwnerUserId,
        UES.UserDisplayName,
        UES.Reputation AS OwnerReputation,
        UES.ReputationTier AS OwnerReputationTier,
        PDE.PostCreationDate,
        PDE.PostAgeInHours,
        PDE.BodyLength,
        PDE.TagsCleaned,
        ARRAY_LENGTH(string_to_array(PDE.TagsCleaned, '><'), 1) AS NumberOfTagsParsed,
        LPH.LastEditDate,
        LPH.ClosedHistoryDate,
        LPH.ReopenedHistoryDate,
        LPH.TotalEditCount,
        LPH.ClosureReasonComment,
        COALESCE(CE.TotalPostComments, 0) AS TotalPostComments,
        COALESCE(CE.AverageCommentScore, 0.0) AS AverageCommentScore,
        CE.LatestCommentDate,
        CE.SecondHighestCommentText,
        PDE.EditedByHighRepUser,
        COALESCE(PLS.LinkedCount, 0) AS ExternalLinkedPosts,
        COALESCE(PLS.DuplicateCount, 0) AS DuplicateRelations,
        -- Window function: Rank posts by score within their post type
        RANK() OVER (PARTITION BY PDE.PostTypeId ORDER BY PDE.PostScore DESC, PDE.PostCreationDate DESC) AS PostTypeScoreRank,
        -- Window function: Calculate cumulative sum of favorite counts for posts by the same owner
        SUM(COALESCE(PDE.FavoriteCount, 0)) OVER (PARTITION BY PDE.OwnerUserId ORDER BY PDE.PostCreationDate) AS CumulativeOwnerFavorites,
        -- Window function: Lag to see view count difference with the immediately older post by the same owner
        COALESCE(PDE.ViewCount - LAG(PDE.ViewCount, 1, 0) OVER (PARTITION BY PDE.OwnerUserId ORDER BY PDE.PostCreationDate), PDE.ViewCount) AS ViewCountDiffFromPrevPost,
        -- Complex expression for post engagement score
        (PDE.PostScore * 0.5) + (COALESCE(PDE.ViewCount, 0) * 0.1) + (COALESCE(PDE.FavoriteCount, 0) * 0.8) + (COALESCE(CE.TotalPostComments, 0) * 0.3) AS EngagementScore,
        -- Complicated predicate in SELECT clause for classification
        CASE
            WHEN PDE.ClosedDate IS NOT NULL AND LPH.ClosedHistoryDate IS NOT NULL AND PDE.PostScore < 0 THEN 'Closed & Negative'
            WHEN PDE.AcceptedAnswerId IS NOT NULL AND PDE.AnswerCount > 0 AND COALESCE(PDE.FavoriteCount, 0) > 10 THEN 'Popular & Answered'
            WHEN COALESCE(PDE.ViewCount, 0) > 5000 AND COALESCE(LPH.TotalEditCount, 0) > 5 THEN 'Highly Viewed & Edited'
            WHEN PDE.TagsCleaned LIKE '%<sql>%' OR PDE.TagsCleaned LIKE '%<database>%' THEN 'SQL/DB Related'
            ELSE 'General Activity'
        END AS PostClassification,
        -- More string manipulation: Extract first tag, handling NULLs
        COALESCE(SPLIT_PART(PDE.TagsCleaned, '><', 1), 'no-tag') AS FirstTag,
        -- Conditional aggregation for vote counts from Votes table directly
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCountOnPost,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCountOnPost
    FROM PostDetailsExtended PDE
    LEFT JOIN UserEngagementStats UES ON PDE.OwnerUserId = UES.UserId
    LEFT JOIN LatestPostHistory LPH ON PDE.PostId = LPH.PostId
    LEFT JOIN CommentEngagement CE ON PDE.PostId = CE.PostId
    LEFT JOIN PostLinkSummary PLS ON PDE.PostId = PLS.PostId
    LEFT JOIN Votes V ON PDE.PostId = V.PostId
    WHERE PDE.PostCreationDate >= (NOW() - INTERVAL '5 year') -- Only recent posts
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_del
        WHERE PH_del.PostId = PDE.PostId
          AND PH_del.PostHistoryTypeId = 12 -- Post Deleted
    )
    GROUP BY
        PDE.Id, PDE.PostTypeId, PDE.PostTypeName, PDE.Title, PDE.PostScore, PDE.ViewCount, PDE.CommentCount,
        PDE.FavoriteCount, PDE.OwnerUserId, UES.UserDisplayName, UES.Reputation, UES.ReputationTier,
        PDE.PostCreationDate, PDE.PostAgeInHours, PDE.BodyLength, PDE.TagsCleaned, LPH.LastEditDate,
        LPH.ClosedHistoryDate, LPH.ReopenedHistoryDate, LPH.TotalEditCount, LPH.ClosureReasonComment,
        CE.TotalPostComments, CE.AverageCommentScore, CE.LatestCommentDate, CE.SecondHighestCommentText,
        PDE.EditedByHighRepUser, PLS.LinkedCount, PLS.DuplicateCount, PDE.ClosedDate,
        PDE.AcceptedAnswerId, PDE.AnswerCount
    HAVING COUNT(V.Id) > 0 -- Ensure there's at least one vote recorded to justify vote aggregation
)
-- Branch 1: Analyze Questions
SELECT
    BQ.PostId,
    BQ.PostTypeName,
    BQ.Title,
    BQ.PostScore,
    BQ.ViewCount,
    BQ.CommentCount,
    BQ.FavoriteCount,
    BQ.OwnerUserId,
    BQ.UserDisplayName,
    BQ.OwnerReputation,
    BQ.OwnerReputationTier,
    BQ.PostCreationDate,
    BQ.PostAgeInHours,
    BQ.BodyLength,
    BQ.TagsCleaned,
    BQ.NumberOfTagsParsed,
    BQ.LastEditDate,
    BQ.ClosedHistoryDate,
    BQ.ReopenedHistoryDate,
    BQ.TotalEditCount,
    BQ.ClosureReasonComment,
    BQ.TotalPostComments,
    BQ.AverageCommentScore,
    BQ.LatestCommentDate,
    BQ.SecondHighestCommentText,
    BQ.EditedByHighRepUser,
    BQ.ExternalLinkedPosts,
    BQ.DuplicateRelations,
    BQ.PostTypeScoreRank,
    BQ.CumulativeOwnerFavorites,
    BQ.ViewCountDiffFromPrevPost,
    BQ.EngagementScore,
    BQ.PostClassification,
    BQ.FirstTag,
    BQ.UpVoteCountOnPost,
    BQ.DownVoteCountOnPost,
    'Question Analysis' AS AnalysisType
FROM BaseQuery BQ
WHERE
    BQ.PostTypeName = 'Question'
    AND (
        (COALESCE(BQ.ViewCount, 0) > 5000 AND BQ.NumberOfTagsParsed >= 3)
        OR (BQ.EngagementScore > 500 AND BQ.ClosedHistoryDate IS NULL)
    )
    AND BQ.TagsCleaned LIKE '%<javascript>%'
    AND BQ.OwnerReputation > 1000
    AND BQ.TotalEditCount BETWEEN 1 AND 10
UNION ALL
-- Branch 2: Analyze Answers
SELECT
    BQ.PostId,
    BQ.PostTypeName,
    NULL AS Title, -- Title is for questions, so NULL for answers
    BQ.PostScore,
    NULL AS ViewCount, -- ViewCount is for questions, so NULL for answers
    BQ.CommentCount,
    BQ.FavoriteCount,
    BQ.OwnerUserId,
    BQ.UserDisplayName,
    BQ.OwnerReputation,
    BQ.OwnerReputationTier,
    BQ.PostCreationDate,
    BQ.PostAgeInHours,
    BQ.BodyLength,
    NULL AS TagsCleaned, -- Tags are for questions, so NULL for answers
    0 AS NumberOfTagsParsed, -- Will be 0 for answers
    BQ.LastEditDate,
    NULL AS ClosedHistoryDate, -- ClosedDate is for questions
    NULL AS ReopenedHistoryDate, -- ReopenedDate is for questions
    BQ.TotalEditCount,
    BQ.ClosureReasonComment, -- This might be 'Not Closed' if no closure history
    BQ.TotalPostComments,
    BQ.AverageCommentScore,
    BQ.LatestCommentDate,
    BQ.SecondHighestCommentText,
    BQ.EditedByHighRepUser,
    BQ.ExternalLinkedPosts,
    BQ.DuplicateRelations,
    BQ.PostTypeScoreRank,
    BQ.CumulativeOwnerFavorites,
    BQ.ViewCountDiffFromPrevPost,
    BQ.EngagementScore,
    BQ.PostClassification,
    'no-tag' AS FirstTag, -- Will be 'no-tag' for answers
    BQ.UpVoteCountOnPost,
    BQ.DownVoteCountOnPost,
    'Answer Analysis' AS AnalysisType
FROM BaseQuery BQ
WHERE
    BQ.PostTypeName = 'Answer'
    AND BQ.PostScore > 50
    AND BQ.PostAgeInHours BETWEEN 24 * 30 AND 24 * 365 * 2 -- Between 1 month and 2 years old
    AND (
        BQ.TotalPostComments > 3
        OR BQ.UpVoteCountOnPost > BQ.DownVoteCountOnPost * 5 -- Highly upvoted answers
    )
    AND BQ.EditedByHighRepUser IS TRUE -- Answers edited by high rep users
ORDER BY
    EngagementScore DESC,
    PostCreationDate DESC,
    PostId
LIMIT 2000;
