-- {"query": "9034.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 3822} 

WITH UserBadgeAgg AS (
    SELECT
        u.Id                          AS UserId,
        u.DisplayName,
        COUNT(b.Id)                   AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(EXTRACT(EPOCH FROM (b.Date - u.CreationDate)) / 86400) AS AvgBadgeLagDays
    FROM Users u
    LEFT JOIN Badges b
        ON b.UserId = u.Id
    WHERE u.Reputation > (
        SELECT AVG(Reputation)
        FROM Users
    )
    GROUP BY u.Id, u.DisplayName
),
PostMetrics AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankWithinType,
        COALESCE((
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id
              AND c.Score > 0
        ), 0)                                AS PositiveComments,
        COALESCE((
            SELECT MAX(v.CreationDate)
            FROM Votes v
            WHERE v.PostId = p.Id
        ), p.CreationDate)                  AS LastVoteDate,
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.PostId = p.Id
              AND pl.LinkTypeId = 1
        )                                    AS OutboundLinks
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '10 years'
),
TagUsage AS (
    SELECT
        t.Id                            AS TagId,
        t.TagName,
        substring(t.TagName FROM 1 FOR 3) AS TagPrefix,
        SUM(
            CASE
                WHEN p.Tags LIKE '%' || t.TagName || '%' THEN 1
                ELSE 0
            END
        )                                AS TagCount,
        COUNT(DISTINCT p.OwnerUserId)    AS DistinctUsers
    FROM Tags t
    FULL OUTER JOIN Posts p
        ON p.PostTypeId = 1
    GROUP BY t.Id, t.TagName
),
TopEngagedPosts AS (
    SELECT
        pm.Id,
        pm.OwnerUserId,
        pm.Score,
        pm.PositiveComments,
        RANK() OVER (ORDER BY pm.PositiveComments DESC, pm.Score DESC) AS EngagementRank
    FROM PostMetrics pm
    WHERE pm.PositiveComments > 10
      AND pm.Score > 0
),
RecentActiveUsers AS (
    SELECT DISTINCT
        u.Id AS UserId
    FROM Users u
    JOIN Posts p
      ON p.OwnerUserId = u.Id
    WHERE p.LastActivityDate > NOW() - INTERVAL '1 month'
),
BenchmarkSet AS (
    SELECT
        uba.UserId,
        uba.DisplayName,
        uba.TotalBadges,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        tep.Id            AS TopPostId,
        tep.Score         AS TopPostScore,
        tep.PositiveComments,
        tu.TagCount,
        tu.DistinctUsers
    FROM UserBadgeAgg uba
    LEFT JOIN TopEngagedPosts tep
      ON tep.OwnerUserId = uba.UserId
    LEFT JOIN TagUsage tu
      ON tu.TagId = (uba.UserId % (SELECT MAX(Id) FROM Tags))
    WHERE uba.TotalBadges > 0
      AND tep.EngagementRank <= 100
),
RecursiveDates AS (
    SELECT date_trunc('month', NOW())::date AS dt
    UNION ALL
    SELECT dt - INTERVAL '1 month'
    FROM RecursiveDates
    WHERE dt > NOW() - INTERVAL '12 months'
)
SELECT
    bs.UserId,
    bs.DisplayName,
    COALESCE(bs.TotalBadges, 0)   AS TotalBadges,
    COALESCE(bs.GoldBadges, 0)    AS GoldBadges,
    COALESCE(bs.SilverBadges, 0)  AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0)  AS BronzeBadges,
    bs.TopPostId,
    bs.TopPostScore,
    bs.PositiveComments,
    bs.TagCount,
    bs.DistinctUsers,
    rd.dt                        AS MonthStart
FROM BenchmarkSet bs
CROSS JOIN RecursiveDates rd
WHERE bs.UserId IN (
    SELECT UserId
    FROM RecentActiveUsers
)
  AND (bs.TagCount > bs.DistinctUsers OR bs.TagCount IS NULL)
ORDER BY rd.dt DESC, bs.TotalBadges DESC, bs.UserId
LIMIT 100 OFFSET 10

UNION

SELECT
    u.Id,
    u.DisplayName,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    u.CreationDate::date AS MonthStart
FROM Users u
WHERE NOT EXISTS (
    SELECT 1
    FROM Badges b
    WHERE b.UserId = u.Id
)

EXCEPT

SELECT
    uba.UserId,
    uba.DisplayName,
    uba.TotalBadges,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    NULL, NULL, NULL, NULL, NULL,
    NULL
FROM UserBadgeAgg uba

INTERSECT

SELECT
    pm.OwnerUserId,
    u.DisplayName,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL
FROM PostMetrics pm
JOIN Users u
  ON u.Id = pm.OwnerUserId
WHERE pm.RankWithinType = 1

ORDER BY 1, 2;
