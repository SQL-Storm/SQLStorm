-- {"query": "58035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1384} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, p.Score
),
PostActivity AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        pt.Name AS PostType,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT p.Tags, '; ') AS FrequentTags,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId BETWEEN 4 AND 9) AS EditCount,
        SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.CreationDate >= NOW() - INTERVAL '1 YEAR'
    GROUP BY p.OwnerUserId, p.PostTypeId, pt.Name
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Reputation,
    pa.PostType,
    pa.LastPostDate,
    pa.FrequentTags,
    pa.EditCount,
    pa.TotalViews,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.TotalBadges,
    au.AvgPostScore,
    au.ReputationRank,
    CASE 
        WHEN pa.TotalViews > 100000 THEN 'High Impact'
        WHEN pa.EditCount > 50 THEN 'Frequent Editor'
        ELSE 'Active Contributor'
    END AS UserCategory
FROM ActiveUsers au
JOIN PostActivity pa ON au.Id = pa.OwnerUserId
WHERE pa.PostTypeId = 1
ORDER BY 
    au.ReputationRank, 
    pa.TotalViews DESC, 
    au.TotalBadges DESC
LIMIT 100;
