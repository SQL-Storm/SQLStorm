-- {"query": "15001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 571}
WITH UserPostActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT v.Id) AS VotesCast,
        AVG(p.Score) AS AvgPostScore,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY COUNT(DISTINCT p.Id) DESC) AS LocationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 100 
      AND u.Location IS NOT NULL
    GROUP BY u.Id, u.Reputation, u.Location
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianTagScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
)
SELECT 
    upa.UserId,
    upa.Reputation,
    upa.TotalPosts,
    upa.VotesCast,
    upa.AvgPostScore,
    tp.TagName,
    tp.PostCount,
    tp.MedianTagScore,
    CASE 
        WHEN upa.TotalPosts > 0 AND tp.PostCount > 100 THEN 
            ROUND(upa.TotalPosts * 100.0 / tp.PostCount, 2)
        ELSE NULL 
    END AS UserTagContributionPercentage,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = upa.UserId 
       AND b.Class = 1) AS GoldBadgeCount
FROM UserPostActivity upa
CROSS JOIN TagPopularity tp
WHERE upa.LocationRank <= 10
    AND tp.PostCount > 50
    AND (upa.Reputation * tp.MedianTagScore) > 10000
ORDER BY UserTagContributionPercentage DESC NULLS LAST
LIMIT 100;
