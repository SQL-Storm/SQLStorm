-- {"query": "4891.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1332} 

WITH RECURSIVE PostHierarchy AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn,
        CAST(p.Id AS VARCHAR(255)) AS path
    FROM Posts p
    WHERE p.ParentId IS NULL -- Start with top-level posts (questions)

    UNION ALL

    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn,
        CAST(ph.path || '->' || CAST(p.Id AS VARCHAR(255)) AS VARCHAR(255)) AS path
    FROM Posts p
    JOIN PostHierarchy ph ON p.ParentId = ph.PostId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT bh.Id) AS TotalBadgeGains,
        CASE WHEN u.DownVotes > u.UpVotes * 2 THEN 'Problematic' WHEN u.Reputation > 100000 THEN 'Expert' WHEN u.Reputation < 1000 THEN 'Newbie' ELSE 'Standard' END AS ReputationTier
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges bh ON u.Id = bh.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.DownVotes, u.UpVotes
),
PostFeatures AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki' ELSE 'User Owned' END AS OwnershipStatus,
        COALESCE(u.DisplayName, 'Deleted User') AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRankByType,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScoreByType,
        SUM(p.Score) OVER () AS TotalScoreAllPosts,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
)
SELECT
    pf.PostId,
    pf.PostType,
    pf.Title,
    pf.Tags,
    pf.PostStatus,
    pf.OwnershipStatus,
    pf.OwnerDisplayName,
    pf.Score,
    pf.AnswerCount,
    pf.CommentCount,
    pf.FavoriteCount,
    pf.ViewCount,
    pf.ScoreRankByType,
    pf.AvgScoreByType,
    pf.TotalScoreAllPosts,
    pf.PreviousPostScore,
    pf.NextPostScore,
    ue.DisplayName AS OwnerDisplayNameFromUsers,
    ue.ReputationTier,
    ue.TotalVotes AS OwnerTotalVotes,
    ue.TotalComments AS OwnerTotalComments,
    ue.TotalBadgeGains AS OwnerTotalBadgeGains,
    CASE WHEN pf.Tags LIKE '%<sql>%' AND pf.Score > 50 THEN 'HighScoringSQLQuestion' WHEN pf.Tags LIKE '%<performance>%' AND pf.AnswerCount > 10 THEN 'PopularPerformanceQuestion' WHEN pf.PostType = 'Answer' AND pf.Score < 0 AND pf.CommentCount > 5 THEN 'ControversialAnswer' ELSE 'Standard' END AS CustomTagCategory
FROM PostFeatures pf
LEFT JOIN UserEngagement ue ON pf.OwnerUserId = ue.UserId
LEFT JOIN PostLinks pl ON pf.Id = pl.PostId OR pf.Id = pl.RelatedPostId
WHERE pf.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) -- Questions with score above average question score
  AND pf.CreationDate BETWEEN '2023-01-01' AND '2023-12-31' -- Filter by a specific year
  AND pf.PostType = 'Question'
  AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = pf.PostId AND c.Text ILIKE '%performance%') -- Questions with 'performance' in comments
  AND pf.OwnerUserId NOT IN (SELECT UserId FROM Badges WHERE Name LIKE '%Tag%') -- Exclude users with tag-based badges
ORDER BY pf.Score DESC, pf.CreationDate DESC
LIMIT 100;
