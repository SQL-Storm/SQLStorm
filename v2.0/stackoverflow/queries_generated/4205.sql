-- {"query": "4205.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1398} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.LastAccessDate DESC) AS LocationAccessRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Views > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.LastAccessDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostType,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostScoreRank,
        AVG(c.Score) OVER (PARTITION BY p.Id) AS AvgCommentScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.Score > 50
    GROUP BY p.Id, p.Title, p.CreationDate, pt.Name, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Score, p.ClosedDate, p.CommunityOwnedDate
),
UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS UserPostCount,
        AVG(p.Score) AS AvgUserPostScore,
        MAX(p.CreationDate) AS LatestUserPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    rua.DisplayName,
    rua.Reputation,
    rua.UserCreationDate,
    rua.TotalPosts,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.ReputationRank,
    rua.LocationAccessRank,
    pe.Title AS PopularPostTitle,
    pe.PostType AS PopularPostType,
    pe.AnswerCount AS PopularPostAnswers,
    pe.CommentCount AS PopularPostComments,
    pe.FavoriteCount AS PopularPostFavorites,
    pe.PostScoreRank AS PopularPostRank,
    pe.AvgCommentScore,
    pe.PostStatus,
    CASE
        WHEN upf.UserPostCount IS NULL THEN 0
        ELSE upf.UserPostCount
    END AS TotalPostsByThisUser,
    CASE
        WHEN upf.AvgUserPostScore IS NULL THEN 0
        ELSE upf.AvgUserPostScore
    END AS AvgScoreOfUserPosts,
    CASE
        WHEN upf.LatestUserPostDate IS NULL THEN 'N/A'
        ELSE CAST(upf.LatestUserPostDate AS VARCHAR)
    END AS LatestPostByThisUser,
    'User Performance Analysis: ' || rua.DisplayName || ' (' || rua.Reputation || ' Rep)' AS AnalysisSummary,
    CASE
        WHEN upf.AvgUserPostScore > 75 AND pe.AvgCommentScore > 3 THEN 'High Engagement & Quality User'
        WHEN rua.ReputationRank <= 100 AND pe.PostScoreRank <= 5 THEN 'Top Performer with Popular Posts'
        WHEN STRFTIME('%Y', 'now') - STRFTIME('%Y', rua.UserCreationDate) > 5 AND rua.TotalPosts > 500 THEN 'Veteran Contributor'
        ELSE 'Standard Contributor'
    END AS PerformanceCategory
FROM RankedUserActivity rua
LEFT JOIN UserPostStats upf ON rua.UserId = upf.OwnerUserId
LEFT JOIN PostEngagement pe ON rua.UserId = pe.OwnerUserId -- Joining to find a popular post by the same user
WHERE EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rua.UserId AND b.Name LIKE '%Master%') -- Users with "Master" badges
UNION
SELECT
    'System Aggregates' AS DisplayName,
    AVG(u.Reputation) AS Reputation,
    MIN(u.CreationDate) AS UserCreationDate,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    NULL AS ReputationRank,
    NULL AS LocationAccessRank,
    NULL AS PopularPostTitle,
    NULL AS PopularPostType,
    NULL AS PopularPostAnswers,
    NULL AS PopularPostComments,
    NULL AS PopularPostFavorites,
    NULL AS PopularPostRank,
    AVG(c.Score) AS AvgCommentScore,
    NULL AS PostStatus,
    COUNT(DISTINCT p.Id) AS TotalPostsByThisUser,
    AVG(p.Score) AS AvgScoreOfUserPosts,
    MAX(p.CreationDate) AS LatestUserPostDate,
    'Overall System Performance Summary' AS AnalysisSummary,
    NULL AS PerformanceCategory
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE u.Views > 500
GROUP BY u.Location
ORDER BY Reputation DESC;
