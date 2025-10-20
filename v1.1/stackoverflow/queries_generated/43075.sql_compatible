WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1, 2) -- Questions and Answers only
    GROUP BY 
        u.Id,
        u.DisplayName,
        u.Reputation
    ORDER BY 
        TotalScore DESC
    LIMIT 100
),
RecentActivePosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        ph.CreationDate AS LastEditDate,
        ph.UserId AS LastEditorId
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5 -- Edit Body
    WHERE 
        p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    ORDER BY 
        p.LastActivityDate DESC
    LIMIT 1000
),
UserActivityMetrics AS (
    SELECT 
        tu.Id,
        AVG(rap.Score) AS AvgPostScore,
        AVG(rap.ViewCount) AS AvgViewCount,
        MAX(rap.AnswerCount) AS MaxAnswers,
        COUNT(rap.Id) AS PostsLast30Days
    FROM 
        TopUsers tu
    JOIN 
        RecentActivePosts rap ON tu.Id = rap.LastEditorId
    GROUP BY 
        tu.Id
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    uam.AvgPostScore,
    uam.AvgViewCount,
    uam.MaxAnswers,
    uam.PostsLast30Days,
    COALESCE(b.BadgeCount, 0) AS BadgeCount
FROM 
    TopUsers tu
JOIN 
    UserActivityMetrics uam ON tu.Id = uam.Id
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(*) AS BadgeCount
    FROM 
        Badges
    GROUP BY 
        UserId
) b ON tu.Id = b.UserId
ORDER BY 
    tu.Reputation DESC,
    uam.AvgPostScore DESC;