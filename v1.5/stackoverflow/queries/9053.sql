WITH
RecentQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        (
            SELECT COUNT(*) 
            FROM Comments c 
            WHERE c.PostId = p.Id
        ) AS CommentCount
    FROM Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '14 days'
),

OwnerQuestionStats AS (
    SELECT
        rq.OwnerUserId,
        COUNT(*)              AS RecentQCount,
        AVG(rq.Score)         AS AvgScore,
        SUM(rq.CommentCount)  AS TotalComments
    FROM RecentQuestions rq
    GROUP BY rq.OwnerUserId
    HAVING COUNT(*) > 3
),

UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*)                                AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

QualifiedUsers AS (
    SELECT
        u.Id                         AS UserId,
        u.DisplayName,
        u.Reputation,
        oqs.RecentQCount,
        oqs.AvgScore,
        oqs.TotalComments,
        COALESCE(ubc.TotalBadges,0)  AS TotalBadges,
        COALESCE(ubc.GoldBadges,0)   AS GoldBadges,
        COALESCE(ubc.SilverBadges,0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges,0) AS BronzeBadges,
        ROW_NUMBER() OVER (
            ORDER BY oqs.TotalComments DESC, oqs.AvgScore DESC
        ) AS rn
    FROM OwnerQuestionStats oqs
    JOIN Users u
      ON u.Id = oqs.OwnerUserId
    LEFT JOIN UserBadgeCounts ubc
      ON ubc.UserId = u.Id
),

TopUsers AS (
    SELECT *
    FROM QualifiedUsers
    WHERE rn <= 5
),

TopUserTags AS (
    SELECT DISTINCT
        t.TagName
    FROM Posts p
    JOIN Tags t
      ON POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    JOIN TopUsers tu
      ON tu.UserId = p.OwnerUserId
),

ActiveTagStats AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id)                                  AS PostCount,
        MAX(p.Score)                                          AS MaxScore,
        MIN(p.Score)                                          AS MinScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score)  AS MedianScore
    FROM Posts p
    JOIN Tags t
      ON POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    GROUP BY t.TagName
),

BenchmarkSet AS (
    SELECT
        ats.TagName,
        ats.PostCount,
        ats.MaxScore,
        ats.MinScore,
        ats.MedianScore
    FROM ActiveTagStats ats
    INNER JOIN TopUserTags tut
      ON tut.TagName = ats.TagName
    WHERE ats.PostCount > 50
),

AllTags AS (
    SELECT TagName
    FROM Tags
),

UnderusedTags AS (
    SELECT TagName
    FROM AllTags
    EXCEPT
    SELECT TagName
    FROM BenchmarkSet
)

SELECT
    bs.TagName                  AS BenchmarkTag,
    ut.TagName                  AS UnderusedTag,
    bs.PostCount,
    bs.MaxScore,
    bs.MinScore,
    bs.MedianScore
FROM BenchmarkSet bs
FULL OUTER JOIN UnderusedTags ut
  ON bs.TagName = ut.TagName
ORDER BY
    COALESCE(bs.PostCount, 0) DESC,
    COALESCE(ut.TagName, '') ASC
LIMIT 100;