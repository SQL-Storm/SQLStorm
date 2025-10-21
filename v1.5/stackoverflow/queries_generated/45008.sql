-- {"query": "45008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 475}
WITH UserTopQuestions AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        p.Id AS PostId, 
        p.Score, 
        p.ViewCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
TagPopularity AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
),
UserBadgeStats AS (
    SELECT 
        UserId, 
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    utq.UserId,
    utq.DisplayName,
    utq.PostId,
    utq.Score,
    utq.ViewCount,
    ubs.BadgeCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    (SELECT TOP 1 TagName FROM TagPopularity ORDER BY PostCount DESC) AS MostPopularTag
FROM UserTopQuestions utq
JOIN UserBadgeStats ubs ON utq.UserId = ubs.UserId
WHERE utq.PostRank <= 3
ORDER BY utq.Score DESC, utq.ViewCount DESC
LIMIT 100;
