-- {"query": "15036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 633}
WITH TopTags AS (
    SELECT 
        t.TagName, 
        t.Count, 
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as TagPopularity,
        AVG(p.Score) OVER (PARTITION BY t.TagName) as AvgTagScore
    FROM Tags t
    LEFT JOIN Posts p ON ARRAY[t.TagName] <@ string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
),
UserContributions AS (
    SELECT 
        u.Id as UserId, 
        u.DisplayName, 
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT 
    COALESCE(tt.TagName, 'Unknown') as TopTag,
    tt.TagPopularity,
    tt.AvgTagScore,
    uc.DisplayName,
    uc.Reputation,
    uc.PostCount,
    uc.VoteCount,
    uc.MedianPostScore,
    CASE 
        WHEN uc.Reputation > 10000 THEN 'High-Rep'
        WHEN uc.Reputation > 1000 THEN 'Mid-Rep'
        ELSE 'Low-Rep'
    END as UserTier,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = uc.UserId) as BadgeCount,
    ROUND(100.0 * uc.PostCount / NULLIF((SELECT COUNT(*) FROM Posts), 0), 2) as PostPercentage
FROM TopTags tt
FULL OUTER JOIN UserContributions uc ON 1=1
WHERE tt.TagPopularity <= 10
    AND uc.PostCount > 0
    AND (
        uc.Reputation > 1000 
        OR EXISTS (
            SELECT 1 
            FROM Badges b 
            WHERE b.UserId = uc.UserId 
              AND b.Class = 1
        )
    )
ORDER BY 
    tt.TagPopularity, 
    uc.Reputation DESC
LIMIT 100;
