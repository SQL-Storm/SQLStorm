-- {"query": "2053.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 490} 
WITH RecentActivePosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title,
        p.OwnerUserId, 
        COALESCE(p.LastActivityDate, p.CreationDate) AS LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COALESCE(p.LastActivityDate, p.CreationDate) DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.PostTypeId IN (1, 2)
        AND p.Score > 0
),
TopRecentActivePosts AS (
    SELECT 
        PostId, 
        Title, 
        OwnerUserId
    FROM 
        RecentActivePosts
    WHERE 
        rn <= 5
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS TotalPosts, 
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName
),
FilteredEngagement AS (
    SELECT 
        ue.UserId, 
        ue.DisplayName, 
        ue.TotalPosts, 
        ue.TotalScore, 
        ue.AvgViewCount,
        COALESCE(b.BadgeCount, 0) AS BadgeCount
    FROM
        UserEngagement ue
    LEFT JOIN (
        SELECT 
            UserId, 
            COUNT(*) AS BadgeCount
        FROM 
            Badges
        WHERE 
            Class IN (1, 2)
        GROUP BY 
            UserId
    ) b ON ue.UserId = b.UserId
)
SELECT 
    te.PostId, 
    te.Title, 
    fe.UserId, 
    fe.DisplayName, 
    fe.TotalPosts, 
    fe.TotalScore, 
    fe.AvgViewCount, 
    fe.BadgeCount
FROM 
    TopRecentActivePosts te
JOIN 
    FilteredEngagement fe ON te.OwnerUserId = fe.UserId
WHERE 
    fe.TotalScore > 10
ORDER BY 
    fe.TotalScore DESC, fe.TotalPosts DESC, te.PostId;