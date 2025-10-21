-- {"query": "45017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 439}
WITH TagPopularity AS (
    SELECT t.TagName, 
           COUNT(p.Id) AS PostCount, 
           AVG(p.Score) AS AvgScore,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViews
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
UserEngagement AS (
    SELECT u.Id, 
           u.Reputation,
           COUNT(DISTINCT p.Id) AS QuestionCount,
           COUNT(DISTINCT v.Id) AS VoteCount,
           COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.Reputation
)
SELECT 
    tp.TagName,
    tp.PostCount,
    tp.AvgScore,
    tp.MedianViews,
    ue.Reputation,
    ue.QuestionCount,
    ue.VoteCount,
    ue.BadgeCount,
    DENSE_RANK() OVER (ORDER BY tp.PostCount DESC) AS TagPopularityRank,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC) AS UserReputationRank
FROM TagPopularity tp
JOIN UserEngagement ue ON 1=1
WHERE tp.PostCount > 100
ORDER BY tp.PostCount DESC, ue.Reputation DESC
LIMIT 500;
