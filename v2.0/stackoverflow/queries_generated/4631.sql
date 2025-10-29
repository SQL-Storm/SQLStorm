-- {"query": "4631.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1646} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
        SUM(p.ViewCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingViewCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserPostEngagement AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AveragePostScore,
        SUM(p.ViewCount) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
RecentUserActivity AS (
    SELECT
        UserId,
        COUNT(Id) AS RecentCommentCount,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS RecentUpvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS RecentDownvotes,
        MAX(CreationDate) AS LastVoteDate
    FROM Votes
    WHERE CreationDate >= DATE('now', '-30 day')
    GROUP BY UserId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ScoreRank,
    rp.PreviousPostScore,
    rp.NextPostScore,
    rp.RollingViewCount,
    CASE
        WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'Highly Engaged Question'
        WHEN rp.Score > 50 AND rp.FavoriteCount > 5 THEN 'Popular Question'
        WHEN rp.Score <= 0 AND rp.AnswerCount = 0 THEN 'Low Engagement Post'
        ELSE 'Standard Post'
    END AS PostEngagementCategory,
    UPPER(SUBSTRING(rp.Title, 1, 1)) || SUBSTRING(rp.Title, 2) AS FormattedTitle,
    CASE
        WHEN upea.TotalPostsOwned IS NULL THEN 0
        ELSE CAST(upea.TotalPostsOwned AS REAL) / (SELECT COUNT(*) FROM Users) * 1000
    END AS UserEngagementRatio,
    COALESCE(rua.RecentCommentCount, 0) AS RecentCommentActivity,
    COALESCE(rua.RecentUpvotes, 0) AS RecentUpvoteActivity,
    COALESCE(rua.RecentDownvotes, 0) AS RecentDownvoteActivity,
    CASE
        WHEN rp.PostCreationDate < rp.LastActivityDate THEN 'Edited'
        ELSE 'Original'
    END AS PostStatus,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostState,
    rp.Score + rp.ViewCount AS ScorePlusViews
FROM RankedPosts rp
LEFT JOIN UserPostEngagement upea ON rp.OwnerUserId = upea.OwnerUserId
LEFT JOIN RecentUserActivity rua ON rp.OwnerUserId = rua.UserId
WHERE rp.ScoreRank <= 100 -- Top 100 by score within each post type
  AND rp.PostCreationDate >= DATE('now', '-365 day') -- Posts from the last year
  AND (rp.Title IS NOT NULL AND LENGTH(rp.Title) > 5) -- Non-trivial titles
  AND rp.OwnerReputation > 500 -- Owners with some reputation
UNION ALL
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ScoreRank,
    rp.PreviousPostScore,
    rp.NextPostScore,
    rp.RollingViewCount,
    CASE
        WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'Highly Engaged Question'
        WHEN rp.Score > 50 AND rp.FavoriteCount > 5 THEN 'Popular Question'
        WHEN rp.Score <= 0 AND rp.AnswerCount = 0 THEN 'Low Engagement Post'
        ELSE 'Standard Post'
    END AS PostEngagementCategory,
    UPPER(SUBSTRING(rp.Title, 1, 1)) || SUBSTRING(rp.Title, 2) AS FormattedTitle,
    CASE
        WHEN upea.TotalPostsOwned IS NULL THEN 0
        ELSE CAST(upea.TotalPostsOwned AS REAL) / (SELECT COUNT(*) FROM Users) * 1000
    END AS UserEngagementRatio,
    COALESCE(rua.RecentCommentCount, 0) AS RecentCommentActivity,
    COALESCE(rua.RecentUpvotes, 0) AS RecentUpvoteActivity,
    COALESCE(rua.RecentDownvotes, 0) AS RecentDownvoteActivity,
    CASE
        WHEN rp.PostCreationDate < rp.LastActivityDate THEN 'Edited'
        ELSE 'Original'
    END AS PostStatus,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostState,
    rp.Score + rp.ViewCount AS ScorePlusViews
FROM RankedPosts rp
LEFT JOIN UserPostEngagement upea ON rp.OwnerUserId = upea.OwnerUserId
LEFT JOIN RecentUserActivity rua ON rp.OwnerUserId = rua.UserId
WHERE rp.ScoreRank > 100 -- Posts not in the top 100
  AND rp.PostCreationDate >= DATE('now', '-90 day') -- Posts from the last 90 days
  AND rp.Score < 0 -- Posts with negative scores
  AND rp.CommentCount > 5 -- Posts with more than 5 comments
ORDER BY rp.PostCreationDate DESC, rp.Score DESC;
