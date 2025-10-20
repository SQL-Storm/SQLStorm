-- {"query": "9010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 1895} 

WITH TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                        AS UserRank,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                                 AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                                 AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                                 AS BronzeBadges,
        AVG(u.Views) OVER ()                                                   AS AvgViewsPerUser
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users)
    GROUP BY u.Id, u.DisplayName
),
RecentQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '30 days'
),
HighActivityPosts AS (
    SELECT
        p.Id,
        p.ViewCount,
        p.CommentCount,
        p.Score,
        p.FavoriteCount
    FROM Posts p
    WHERE p.ViewCount   > 1000
      AND p.CommentCount > 5
),
TaggedPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS TotalTaggedPosts,
        STRING_AGG(DISTINCT regexp_split_to_table(
                       substring(Tags, 2, length(Tags)-2), '><'
                   ), ',') AS AllTags
    FROM Posts
    WHERE Tags IS NOT NULL
    GROUP BY OwnerUserId
),
Combined AS (
    SELECT
        tu.Id,
        tu.DisplayName,
        tu.UserRank,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.AvgViewsPerUser,
        rq.Title            AS RecentTitle,
        rq.CreationDate     AS RecentQDate,
        hap.ViewCount       AS RecentQViews,
        tpc.TotalTaggedPosts,
        tpc.AllTags
    FROM TopUsers tu
    LEFT JOIN RecentQuestions rq
      ON rq.OwnerUserId = tu.Id
     AND rq.QRank = 1
    LEFT JOIN HighActivityPosts hap
      ON hap.Id = rq.Id
    LEFT JOIN TaggedPostCounts tpc
      ON tpc.OwnerUserId = tu.Id
)
SELECT
    c.DisplayName,
    c.UserRank,
    COALESCE(c.RecentTitle, '<no recent question>')                          AS RecentQuestionTitle,
    TO_CHAR(c.RecentQDate, 'YYYY-MM-DD')                                      AS RecentQDate,
    c.RecentQViews,
    CASE
        WHEN c.GoldBadges   > 0 THEN 'HasGold'
        WHEN c.SilverBadges > 0 THEN 'HasSilverOnly'
        ELSE 'NoMajorBadges'
    END                                                                       AS BadgeStatus,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = c.Id AND v.VoteTypeId = 5) AS FavoriteVotes,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = c.Id)             AS MaxPostScore,
    c.TotalTaggedPosts,
    c.AllTags
FROM Combined c
WHERE c.UserRank <= 100
  AND (c.GoldBadges + c.SilverBadges + c.BronzeBadges) >= 5
UNION ALL
SELECT
    u.DisplayName,
    NULL        AS UserRank,
    'SQL Enthusiast'      AS RecentQuestionTitle,
    NULL        AS RecentQDate,
    NULL        AS RecentQViews,
    'UnionedUser'         AS BadgeStatus,
    NULL        AS FavoriteVotes,
    NULL        AS MaxPostScore,
    NULL        AS TotalTaggedPosts,
    NULL        AS AllTags
FROM Users u
WHERE EXISTS (
    SELECT 1
    FROM Badges b
    WHERE b.UserId = u.Id
      AND b.Name ILIKE '%SQL%'
)
INTERSECT
SELECT
    DisplayName,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM Users
WHERE Location LIKE '%Database%'
ORDER BY UserRank NULLS LAST, DisplayName;
