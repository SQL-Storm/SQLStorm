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
    JOIN Posts p ON POSITION(t.TagName IN p.Tags) > 0
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
    COALESCE(ubs.BadgeCount, 0) AS BadgeCount,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    (SELECT TagName 
     FROM TagPopularity
     ORDER BY PostCount DESC
     LIMIT 1) AS MostPopularTag
FROM UserTopQuestions utq
LEFT JOIN UserBadgeStats ubs ON utq.UserId = ubs.UserId
WHERE utq.PostRank <= 3
ORDER BY utq.Score DESC, utq.ViewCount DESC
FETCH FIRST 100 ROWS ONLY;