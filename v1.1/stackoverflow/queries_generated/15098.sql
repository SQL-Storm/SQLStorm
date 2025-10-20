-- {"query": "15098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 231165, "output_tokens": 68233} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AvgPostScore,
        FIRST_VALUE(p.Title) OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS LatestPostTitle,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostCountRank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE p.PostTypeId = 1 AND u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS TagPostCount,
        CASE 
            WHEN COUNT(p.Id) > 1000 THEN 'Extremely Popular'
            WHEN COUNT(p.Id) > 500 THEN 'Very Popular'
            WHEN COUNT(p.Id) > 100 THEN 'Popular'
            ELSE 'Niche'
        END AS PopularityCategory
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.PostCount,
    uas.VoteCount,
    uas.AvgPostScore,
    uas.LatestPostTitle,
    uas.PostCountRank,
    uas.MedianViewCount,
    (SELECT STRING_AGG(tp.TagName || '(' || tp.PopularityCategory || ')', ', ')
     FROM TagPopularity tp
     JOIN Posts p ON p.Tags LIKE '%' || tp.TagName || '%'
     WHERE p.OwnerUserId = uas.UserId
     LIMIT 5) AS TopTags,
    COALESCE(
        (SELECT SUM(v.BountyAmount) 
         FROM Votes v 
         WHERE v.UserId = uas.UserId AND v.VoteTypeId = 8), 
        0
    ) AS TotalBountyStarted
FROM UserActivityStats uas
WHERE uas.PostCount > 10
ORDER BY uas.PostCount DESC, uas.AvgPostScore DESC
LIMIT 100;