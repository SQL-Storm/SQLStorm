-- {"query": "1411.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3533} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        COALESCE(u.Views, 0) AS UserTotalViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreOwned,
        AVG(COALESCE(p.Score, 0)) AS AveragePostScoreOwned,
        MAX(p.CreationDate) AS LastPostCreationDate,
        MIN(p.CreationDate) AS FirstPostCreationDate,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        LAG(u.DisplayName, 1, 'N/A') OVER (ORDER BY u.Reputation DESC) AS PreviousRepUserDisplayName,
        NTILE(10) OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS ReputationDecile,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedByPosts,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedByPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Title,
        p.Body,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        p.ClosedDate IS NOT NULL AS IsClosed,
        REPLACE(REPLACE(REPLACE(SUBSTRING(p.Title, 1, POSITION(' ' IN p.Title) - 1), '''', ''), '"', ''), '.', '') AS FirstWordSanitizedTitle,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(p.LastEditDate, p.CreationDate) AS EffectiveLastEditDate,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostByOwnerCreationDate,
        (SELECT COUNT(DISTINCT ph.UserId) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS UniqueEditorsOnPostCount,
        (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 5 AND ph.UserId = p.OwnerUserId) AS LastOwnerBodyEditDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
),
TagUsageMetrics AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS TotalPostsWithTag,
        AVG(p.Score) AS AvgScoreForTag,
        SUM(p.ViewCount) AS TotalViewsForTag,
        MAX(p.CreationDate) AS LatestTagUsageDate
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE ('%' || t.TagName || '%') -- Simple tag search, for full parsing see comments in schema
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 50 AND AVG(p.Score) > 5
),
PostLinkAggregates AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostsCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
VoteDetailAggregates AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PostUpvotesCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS PostDownvotesCount,
        SUM(CASE WHEN v.VoteTypeId = 4 THEN 1 ELSE 0 END) AS PostOffensiveVotesCount,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerVotesCount
    FROM Votes v
    GROUP BY v.PostId
),
RecentPostComments AS (
    SELECT DISTINCT ON (c.PostId)
        c.PostId,
        c.Text AS MostRecentCommentText,
        c.CreationDate AS MostRecentCommentDate,
        c.UserId AS MostRecentCommenterId
    FROM Comments c
    ORDER BY c.PostId, c.CreationDate DESC
)
-- Main query combining multiple CTEs and complex logic
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPostsOwned,
    uas.TotalQuestionsOwned,
    uas.TotalAnswersOwned,
    uas.AveragePostScoreOwned,
    uas.ReputationRank,
    uas.ReputationDecile,
    pca.PostId,
    pca.PostTypeName,
    COALESCE(pca.Title, 'Untitled Post') AS PostTitle,
    pca.Score AS PostScore,
    pca.ViewCount AS PostViewCount,
    pca.AnswerCount,
    pca.CommentCount,
    pca.FavoriteCount,
    pca.IsClosed,
    pca.BodyLength,
    pca.FirstWordSanitizedTitle,
    pca.NextPostByOwnerCreationDate,
    pca.UniqueEditorsOnPostCount,
    pca.LastOwnerBodyEditDate,
    pla.LinkedPostsCount,
    pla.DuplicatePostsCount,
    vda.PostUpvotesCount,
    vda.PostDownvotesCount,
    vda.PostOffensiveVotesCount,
    vda.AcceptedAnswerVotesCount,
    tma.TagName AS TopAssociatedTag,
    tma.AvgScoreForTag,
    tma.TotalViewsForTag,
    rpc.MostRecentCommentText,
    rpc.MostRecentCommentDate,
    rpc.MostRecentCommenterId,
    CASE
        WHEN uas.Reputation > 20000 AND pca.Score > 100 THEN 'Elite Contributor'
        WHEN uas.Reputation > 5000 AND pca.Score > 20 AND pca.PostTypeId = 1 THEN 'High-Impact Questioner'
        WHEN uas.Reputation > 5000 AND pca.Score > 20 AND pca.PostTypeId = 2 THEN 'High-Impact Answerer'
        WHEN uas.Reputation > 1000 AND pca.BodyLength > 500 THEN 'Detailed Contributor'
        ELSE 'General Participant'
    END AS UserPostImpactCategory,
    NULLIF(pca.ViewCount, 0) / NULLIF(pca.AnswerCount, 0) AS ViewToAnswerRatio,
    (EXTRACT(EPOCH FROM (uas.LastAccessDate - uas.UserCreationDate)) / 86400.0) AS DaysActiveSinceCreation,
    UPPER(SUBSTRING(COALESCE(pca.Title, 'NO TITLE'), 1, 1)) || SUBSTRING(COALESCE(pca.Title, 'NO TITLE'), 2) AS CapitalizedTitle,
    REPLACE(REPLACE(SUBSTRING(COALESCE(pca.Body, ''), 1, 150), E'\n', ' '), '  ', ' ') || '...' AS BodySnippet,
    ROW_NUMBER() OVER (PARTITION BY uas.UserId ORDER BY pca.PostCreationDate DESC) AS UserPostSequenceNumber,
    AVG(pca.Score) OVER (PARTITION BY uas.Location) AS AverageScorePerUserLocation,
    PERCENT_RANK() OVER (ORDER BY uas.Reputation DESC) AS UserReputationPercentRank,
    (uas.UserUpVotesGiven * 0.7 + uas.TotalUpvotesReceivedByPosts * 0.3) AS WeightedUserEngagementScore,
    pca.PostCreationDate - pca.LastActivityDate AS TimeSinceLastActivity
FROM UserActivitySummary uas
LEFT JOIN PostContentAnalysis pca ON uas.UserId = pca.OwnerUserId
LEFT JOIN PostLinkAggregates pla ON pca.PostId = pla.PostId
LEFT JOIN VoteDetailAggregates vda ON pca.PostId = vda.PostId
LEFT JOIN RecentPostComments rpc ON pca.PostId = rpc.PostId
LEFT JOIN TagUsageMetrics tma ON pca.Tags LIKE ('%' || tma.TagName || '%') -- Heuristic tag match for top tag
WHERE
    uas.TotalPostsOwned > 0
    AND pca.PostTypeName IS NOT NULL
    AND (
        (pca.Score > (uas.AveragePostScoreOwned * 1.2) AND pca.ViewCount > 500 AND pca.PostTypeId = 1) -- High-scoring, high-view questions
        OR (pca.AnswerCount > 3 AND pca.IsClosed = FALSE AND pca.PostTypeId = 1) -- Active questions
        OR (pca.PostTypeId = 2 AND pca.Score > 15 AND pca.BodyLength > 200) -- Detailed, high-scoring answers
    )
    AND NOT EXISTS ( -- Correlated subquery: user has no 'Beta' badge created after their last activity
        SELECT 1
        FROM Badges b
        WHERE b.UserId = uas.UserId
        AND b.Name ILIKE '%Beta%'
        AND b.Date > uas.LastAccessDate
    )
    AND (
        (pca.Title IS NOT NULL AND pca.Title ILIKE '%problem%' AND pca.CommentCount > 0) -- Posts with "problem" and comments
        OR (pca.Title IS NULL AND pca.Body ILIKE '%solution%') -- Untitles posts suggesting solutions
    )
    AND COALESCE(pca.LastOwnerBodyEditDate, pca.PostCreationDate) < (NOW() - INTERVAL '3 months') -- Posts not recently edited by owner
    AND (pca.FavoriteCount IS NULL OR pca.FavoriteCount < 50) -- Not extremely popular (to find different segment)

UNION ALL

-- Second branch: Focus on posts with significant history changes, owned by high-reputation users, with associated tags
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.TotalPostsOwned,
    uas.TotalQuestionsOwned,
    uas.TotalAnswersOwned,
    uas.AveragePostScoreOwned,
    uas.ReputationRank,
    uas.ReputationDecile,
    pca.PostId,
    pca.PostTypeName,
    COALESCE(pca.Title, 'Untitled Post') AS PostTitle,
    pca.Score AS PostScore,
    pca.ViewCount AS PostViewCount,
    pca.AnswerCount,
    pca.CommentCount,
    pca.FavoriteCount,
    pca.IsClosed,
    pca.BodyLength,
    pca.FirstWordSanitizedTitle,
    pca.NextPostByOwnerCreationDate,
    pca.UniqueEditorsOnPostCount,
    pca.LastOwnerBodyEditDate,
    pla.LinkedPostsCount,
    pla.DuplicatePostsCount,
    vda.PostUpvotesCount,
    vda.PostDownvotesCount,
    vda.PostOffensiveVotesCount,
    vda.AcceptedAnswerVotesCount,
    tma.TagName AS TopAssociatedTag,
    tma.AvgScoreForTag,
    tma.TotalViewsForTag,
    rpc.MostRecentCommentText,
    rpc.MostRecentCommentDate,
    rpc.MostRecentCommenterId,
    'Historical Significance Watch' AS UserPostImpactCategory,
    NULLIF(pca.ViewCount, 0) / NULLIF(pca.AnswerCount, 0) AS ViewToAnswerRatio,
    (EXTRACT(EPOCH FROM (uas.LastAccessDate - uas.UserCreationDate)) / 86400.0) AS DaysActiveSinceCreation,
    UPPER(SUBSTRING(COALESCE(pca.Title, 'NO TITLE'), 1, 1)) || SUBSTRING(COALESCE(pca.Title, 'NO TITLE'), 2) AS CapitalizedTitle,
    REPLACE(REPLACE(SUBSTRING(COALESCE(pca.Body, ''), 1, 150), E'\n', ' '), '  ', ' ') || '...' AS BodySnippet,
    ROW_NUMBER() OVER (PARTITION BY uas.UserId ORDER BY pca.PostCreationDate DESC) AS UserPostSequenceNumber,
    AVG(pca.Score) OVER (PARTITION BY uas.Location) AS AverageScorePerUserLocation,
    PERCENT_RANK() OVER (ORDER BY uas.Reputation DESC) AS UserReputationPercentRank,
    (uas.UserUpVotesGiven * 0.7 + uas.TotalUpvotesReceivedByPosts * 0.3) AS WeightedUserEngagementScore,
    pca.PostCreationDate - pca.LastActivityDate AS TimeSinceLastActivity
FROM UserActivitySummary uas
JOIN PostContentAnalysis pca ON uas.UserId = pca.OwnerUserId
LEFT JOIN PostLinkAggregates pla ON pca.PostId = pla.PostId
LEFT JOIN VoteDetailAggregates vda ON pca.PostId = vda.PostId
LEFT JOIN RecentPostComments rpc ON pca.PostId = rpc.PostId
LEFT JOIN TagUsageMetrics tma ON pca.Tags LIKE ('%' || tma.TagName || '%')
WHERE
    uas.Reputation > 15000 -- High reputation users
    AND pca.UniqueEditorsOnPostCount > 2 -- Posts edited by multiple users
    AND pca.PostTypeName = 'Question' -- Only questions
    AND pca.IsClosed = TRUE -- Closed questions
    AND EXISTS ( -- Correlated subquery: check if the closed question has been reopened at least once
        SELECT 1
        FROM PostHistory ph
        WHERE ph.PostId = pca.PostId
        AND ph.PostHistoryTypeId = 11 -- Post Reopened
    )
ORDER BY ReputationRank ASC, PostScore DESC
LIMIT 2000;
