WITH
RecentPosts AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.CreationDate DESC
        ) AS rn
    FROM Posts p
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(rp.PostId) AS RecentPostCount,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS RecentQuestions,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS RecentAnswers
    FROM Users u
    LEFT JOIN RecentPosts rp
      ON rp.OwnerUserId = u.Id
    WHERE u.CreationDate < CAST('2024-10-01 12:34:56' AS TIMESTAMP)
      AND u.Reputation > 0
    GROUP BY u.Id, u.DisplayName
),
TagUsage AS (
    SELECT
        p.OwnerUserId AS UserId,
        UNNEST(
          STRING_TO_ARRAY(
            SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2),
            '><'
          )
        ) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
TopTags AS (
    SELECT
        tu.UserId,
        tu.TagName,
        COUNT(*) AS TagCount,
        RANK() OVER (
          PARTITION BY tu.UserId
          ORDER BY COUNT(*) DESC
        ) AS rk
    FROM TagUsage tu
    GROUP BY tu.UserId, tu.TagName
    HAVING COUNT(*) > 5
),
UserTopTag AS (
    SELECT
        UserId,
        TagName AS TopTag
    FROM TopTags
    WHERE rk = 1
),
BadgeSummary AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
Combined AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.RecentPostCount,
        ua.RecentQuestions,
        ua.RecentAnswers,
        COALESCE(bs.GoldBadges, 0) AS GoldBadges,
        COALESCE(bs.SilverBadges, 0) AS SilverBadges,
        COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
        utt.TopTag
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs ON bs.UserId = ua.UserId
    FULL OUTER JOIN UserTopTag utt ON utt.UserId = ua.UserId
),
HighPerformers AS (
    SELECT
        c.*,
        (CAST(c.RecentAnswers AS FLOAT) / NULLIF(c.RecentQuestions, 0)) AS AnsToQRatio,
        ROW_NUMBER() OVER (
            ORDER BY c.RecentPostCount DESC, c.GoldBadges DESC
        ) AS PerformanceRank
    FROM Combined c
),
Selected AS (
    SELECT * FROM HighPerformers WHERE PerformanceRank < 50
    INTERSECT
    SELECT * FROM HighPerformers WHERE GoldBadges > 1
)
SELECT
    s.UserId,
    s.DisplayName,
    s.RecentPostCount,
    s.RecentQuestions,
    s.RecentAnswers,
    s.GoldBadges,
    s.SilverBadges,
    s.BronzeBadges,
    s.TopTag,
    s.AnsToQRatio,
    s.PerformanceRank,
    EXISTS (
      SELECT 1
      FROM Posts p
      WHERE p.OwnerUserId = s.UserId
        AND p.ViewCount > 10000
    ) AS HasHighViewPost
FROM Selected s
ORDER BY s.PerformanceRank;