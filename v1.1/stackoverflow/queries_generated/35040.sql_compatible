WITH TopTags AS (
    SELECT t.TagName, SUM(t.Count) AS TotalUses
    FROM Tags t
    GROUP BY t.TagName
    ORDER BY TotalUses DESC
    LIMIT 10
),
ActiveUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, COUNT(p.Id) AS PostCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 10
),
TagUserActivity AS (
    SELECT
        tt.TagName,
        au.UserId,
        au.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsWithTag,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViews
    FROM TopTags tt
    JOIN Posts p ON p.Tags LIKE '%' || '<' || tt.TagName || '>' || '%'
    JOIN ActiveUsers au ON au.UserId = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY tt.TagName, au.UserId, au.DisplayName
),
UserBadges AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
PopularQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
      AND p.ViewCount > 1000
      AND p.Score > 10
)
SELECT
    tua.TagName,
    tua.DisplayName AS User,
    tua.PostsWithTag,
    tua.TotalScore,
    tua.AvgViews,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    pq.Title AS PopularQuestion,
    pq.ViewCount AS PQ_Views,
    pq.Score AS PQ_Score,
    pq.AnswerCount AS PQ_Answers
FROM TagUserActivity tua
LEFT JOIN UserBadges ub ON tua.UserId = ub.UserId
LEFT JOIN PopularQuestions pq ON pq.OwnerUserId = tua.UserId AND pq.Title IS NOT NULL
ORDER BY tua.TagName, tua.PostsWithTag DESC, tua.TotalScore DESC, pq.ViewCount DESC
LIMIT 100;