-- {"query": "15024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 58375, "output_tokens": 17442} 
WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Name) AS UniqueBadgeCount,
        AVG(CASE WHEN b.Class = 1 THEN 1.0 WHEN b.Class = 2 THEN 0.5 ELSE 0.25 END) AS WeightedBadgeQuality,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        v.UpvoteCount,
        v.DownvoteCount,
        (v.UpvoteCount - v.DownvoteCount) AS NetVotes,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
        FROM Votes
        GROUP BY PostId
    ) v ON p.Id = v.PostId
)
SELECT 
    ubs.UserId,
    ubs.DisplayName,
    ubs.UniqueBadgeCount,
    ubs.WeightedBadgeQuality,
    pp.PostId,
    pp.PostTypeId,
    pp.Score,
    pp.ViewCount,
    pp.NetVotes,
    COALESCE(pl.DuplicateLinks, 0) AS DuplicateLinkCount,
    CASE 
        WHEN pp.ScoreRank <= 10 THEN 'Top Performer'
        WHEN pp.Score > 10 THEN 'High Impact'
        ELSE 'Standard'
    END AS PostCategory,
    ROUND(pp.NetVotes * 1.0 / NULLIF(pp.ViewCount, 0), 4) AS VoteEngagementRatio
FROM UserBadgeStats ubs
JOIN PostPerformance pp ON ubs.UserId = pp.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS DuplicateLinks
    FROM PostLinks 
    WHERE LinkTypeId = 3 
    GROUP BY PostId
) pl ON pp.PostId = pl.PostId
WHERE 
    ubs.UniqueBadgeCount > 3 
    AND pp.PostTypeId IN (1, 2)
    AND (pl.DuplicateLinks IS NULL OR pl.DuplicateLinks < 5)
ORDER BY VoteEngagementRatio DESC
LIMIT 100;