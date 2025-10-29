WITH
    UserPostAgg AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
            SUM(p.Score) AS TotalScore,
            AVG(p.Score) AS AvgScore,
            COUNT(CASE WHEN p.PostTypeId = 2
                       AND EXISTS (
                           SELECT 1
                           FROM Posts a
                           WHERE a.Id = p.AcceptedAnswerId
                             AND a.OwnerUserId = p.OwnerUserId
                       ) THEN 1 END) AS SelfAcceptedCount
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    UserBadgeAgg AS (
        SELECT
            b.UserId,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
            COUNT(CASE WHEN b.TagBased = true THEN 1 END) AS TagBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    UserRecentActivity AS (
        SELECT
            u.Id AS UserId,
            GREATEST(
                COALESCE(u.LastAccessDate, TIMESTAMP '1970-01-01'),
                COALESCE(
                    (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id),
                    TIMESTAMP '1970-01-01'
                ),
                COALESCE(
                    (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = u.Id),
                    TIMESTAMP '1970-01-01'
                )
            ) AS LastActive
        FROM Users u
    ),
    TagExplode AS (
        SELECT
            OwnerUserId,
            unnest(string_to_array(trim(both '<>' FROM Tags), '><')) AS Tag
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
          AND Tags IS NOT NULL
    ),
    GlobalTagCounts AS (
        SELECT
            Tag,
            COUNT(*) AS GlobalCount
        FROM (
            SELECT unnest(string_to_array(trim(both '<>' FROM Tags), '><')) AS Tag
            FROM Posts
            WHERE Tags IS NOT NULL
        ) t
        GROUP BY Tag
    ),
    UserTopTag AS (
        SELECT
            te.OwnerUserId AS UserId,
            te.Tag,
            gt.GlobalCount,
            ROW_NUMBER() OVER (PARTITION BY te.OwnerUserId ORDER BY gt.GlobalCount DESC) AS rn
        FROM TagExplode te
        JOIN GlobalTagCounts gt ON gt.Tag = te.Tag
    ),
    UserTagScore AS (
        SELECT
            utt.UserId,
            utt.Tag AS TopTag,
            utt.GlobalCount AS TopTagGlobalUsage
        FROM UserTopTag utt
        WHERE utt.rn = 1
    ),
    Combined AS (
        SELECT
            u.Id,
            u.DisplayName,
            COALESCE(up.QuestionCount,0) AS QuestionCount,
            COALESCE(up.AnswerCount,0) AS AnswerCount,
            COALESCE(up.TotalScore,0) AS TotalScore,
            COALESCE(ub.GoldBadges,0) AS GoldBadges,
            COALESCE(ub.SilverBadges,0) AS SilverBadges,
            COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
            COALESCE(ub.TagBadges,0) AS TagBadges,
            ra.LastActive,
            COALESCE(uts.TopTag,'<none>') AS TopTag,
            COALESCE(uts.TopTagGlobalUsage,0) AS TopTagGlobalUsage,
            (
                u.Reputation * 0.6
                + COALESCE(up.TotalScore,0) * 0.2
                + COALESCE(ub.GoldBadges,0) * 100
                + COALESCE(ub.SilverBadges,0) * 50
                + COALESCE(ub.BronzeBadges,0) * 10
                - EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ra.LastActive))/86400 * 2
            ) AS CompositeScore
        FROM Users u
        LEFT JOIN UserPostAgg up ON up.UserId = u.Id
        LEFT JOIN UserBadgeAgg ub ON ub.UserId = u.Id
        LEFT JOIN UserRecentActivity ra ON ra.UserId = u.Id
        LEFT JOIN UserTagScore uts ON uts.UserId = u.Id
    ),
    Ranked AS (
        SELECT
            c.*,
            ROW_NUMBER() OVER (ORDER BY CompositeScore DESC) AS Rank,
            PERCENT_RANK() OVER (ORDER BY CompositeScore DESC) AS Percentile
        FROM Combined c
        WHERE CompositeScore IS NOT NULL
    )
SELECT *
FROM Ranked
WHERE Rank <= 100

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    0 AS QuestionCount,
    0 AS AnswerCount,
    0 AS TotalScore,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS TagBadges,
    u.LastAccessDate AS LastActive,
    '<no posts>' AS TopTag,
    0 AS TopTagGlobalUsage,
    u.Reputation * 0.6 AS CompositeScore,
    NULL AS Rank,
    NULL AS Percentile
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation > 20000
ORDER BY CompositeScore DESC
LIMIT 150;