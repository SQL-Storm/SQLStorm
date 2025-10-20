-- {"query": "45086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 197284, "output_tokens": 34788} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.CreationDate) AS LatestPostDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
), 
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        t.TagName
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.TotalPosts,
    ups.TotalPostScore,
    ups.AvgViewCount,
    tp.TagName AS MostPopularTag,
    tp.PostCount AS TagPostCount,
    tp.AvgTagScore,
    b.Name AS TopBadge
FROM 
    UserPostStats ups
JOIN 
    TagPopularity tp ON tp.PostCount = (
        SELECT MAX(PostCount) 
        FROM TagPopularity
    )
LEFT JOIN 
    Badges b ON b.UserId = ups.UserId AND b.Class = 1
WHERE 
    ups.TotalPosts > 10
ORDER BY 
    ups.TotalPostScore DESC, 
    ups.AvgViewCount DESC
LIMIT 100;