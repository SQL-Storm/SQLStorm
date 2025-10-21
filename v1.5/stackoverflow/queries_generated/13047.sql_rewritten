-- {"query": "13047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 596} 
WITH TopUserBadges AS (
    SELECT 
        UserId,
        Name,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Class ASC, Date ASC) AS BadgeRank
    FROM Badges
    WHERE Class BETWEEN 1 AND 3
),
UserPostActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        AVG(p.Score) AS AvgPostScore,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8)
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date) - INTERVAL '1 year')
    GROUP BY u.Id
),
ComplexMetrics AS (
    SELECT 
        upa.UserId,
        upa.TotalPosts,
        COALESCE(upa.AvgPostScore, 0) AS AvgPostScore,
        COALESCE(upa.EditCount, 0) AS EditCount,
        COALESCE(upa.LastEditDate, '1900-01-01') AS LastEditDate,
        COALESCE(t.Name, 'No Badge') AS FirstBadgeName,
        ROW_NUMBER() OVER (ORDER BY COALESCE(upa.AvgPostScore, 0) DESC, COALESCE(upa.TotalPosts, 0) DESC) AS PerformanceRank
    FROM UserPostActivity upa
    LEFT JOIN TopUserBadges t ON upa.UserId = t.UserId AND t.BadgeRank = 1
    WHERE upa.TotalPosts > (SELECT AVG(TotalPosts) FROM UserPostActivity WHERE TotalPosts > 0)
)
SELECT 
    u.DisplayName,
    cm.TotalPosts,
    ROUND(cm.AvgPostScore, 2) AS AvgScore,
    cm.EditCount,
    cm.LastEditDate,
    cm.FirstBadgeName,
    cm.PerformanceRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = cm.UserId) AS TotalComments
FROM ComplexMetrics cm
JOIN Users u ON cm.UserId = u.Id
WHERE cm.PerformanceRank <= 10
ORDER BY cm.PerformanceRank;