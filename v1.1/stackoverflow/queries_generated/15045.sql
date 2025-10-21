-- {"query": "15045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 555}
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY u.Id) AS TotalUpvotes,
        COALESCE(NULLIF(p.AnswerCount, 0), 1) * 
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) AS PostEngagementScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
), TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        SUM(PostEngagementScore) AS TotalContributionScore,
        AVG(Score) AS AveragePostScore,
        COUNT(DISTINCT PostId) AS UniquePostCount
    FROM RankedUserPosts
    WHERE PostRank <= 5
    GROUP BY UserId, DisplayName
    HAVING COUNT(DISTINCT PostId) > 3
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.TotalContributionScore,
    tc.AveragePostScore,
    tc.UniquePostCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = tc.UserId AND b.Class = 1) AS GoldBadgeCount,
    DENSE_RANK() OVER (ORDER BY tc.TotalContributionScore DESC) AS ContributorRank
FROM TopContributors tc
JOIN Users u ON tc.UserId = u.Id
WHERE u.Reputation > 1000
    AND EXISTS (
        SELECT 1 
        FROM Badges b 
        WHERE b.UserId = tc.UserId 
          AND b.Class = 1
    )
ORDER BY tc.TotalContributionScore DESC
LIMIT 25;
