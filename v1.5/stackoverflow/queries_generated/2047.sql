-- {"query": "2047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 394} 

WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        RANK() OVER (ORDER BY MAX(p.LastActivityDate) DESC) AS ActivityRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        u.Id, u.DisplayName
),
TopScoredPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        SUM(v.VoteTypeId = 2) - SUM(v.VoteTypeId = 3) AS NetScore
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > CURRENT_DATE - INTERVAL '1 month'
    GROUP BY 
        p.Id, p.Title
    HAVING 
        NetScore > 10
),
BadgedUsers AS (
    SELECT 
        u.Id AS UserId, 
        COUNT(DISTINCT b.Name) AS UniqueBadges
    FROM 
        Users u
    INNER JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
)
SELECT 
    rau.DisplayName, 
    tsp.Title AS TopPostTitle,
    COALESCE(bu.UniqueBadges, 0) AS UniqueBadgeCount
FROM 
    RecentActiveUsers rau
LEFT JOIN 
    TopScoredPosts tsp ON rau.UserId = tsp.PostId
LEFT JOIN 
    BadgedUsers bu ON rau.UserId = bu.UserId
WHERE 
    tsp.NetScore IS NOT NULL 
    OR bu.UniqueBadges > 5
ORDER BY 
    rau.ActivityRank, bu.UniqueBadges DESC, tsp.NetScore DESC
LIMIT 50;
