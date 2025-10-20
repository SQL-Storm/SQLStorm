-- {"query": "15065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 154110, "output_tokens": 45300} 
WITH UserTagStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName, Id FROM Posts) t ON t.Id = p.Id
    WHERE u.Reputation > 1000 AND p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
),
TagPopularity AS (
    SELECT 
        uts.TagName,
        COUNT(DISTINCT uts.UserId) AS UserCount,
        SUM(uts.PostCount) AS TotalPosts,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY uts.AvgPostScore) AS MedianTagScore
    FROM UserTagStats uts
    WHERE uts.TagRank <= 3
    GROUP BY uts.TagName
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    tp.TagName,
    tp.UserCount AS TagUserCount,
    tp.TotalPosts,
    uts.PostCount AS UserTagPostCount,
    uts.AvgPostScore,
    tp.MedianTagScore,
    CASE 
        WHEN uts.AvgPostScore > tp.MedianTagScore THEN 'Above Average'
        WHEN uts.AvgPostScore < tp.MedianTagScore THEN 'Below Average'
        ELSE 'Average'
    END AS ScorePerformance,
    DATEDIFF(day, u.CreationDate, uts.LastPostDate) AS DaysSinceFirstPost,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.TagBased = TRUE) AS TagBadgeCount
FROM UserTagStats uts
JOIN Users u ON uts.UserId = u.Id
JOIN TagPopularity tp ON uts.TagName = tp.TagName
WHERE 
    uts.TagRank = 1 
    AND tp.UserCount > 10 
    AND uts.PostCount > 5
ORDER BY 
    tp.TotalPosts DESC, 
    uts.AvgPostScore DESC
LIMIT 100;