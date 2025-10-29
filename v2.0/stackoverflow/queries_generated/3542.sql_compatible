WITH
    UserPosts AS (
        SELECT
            u.Id                         AS UserId,
            u.DisplayName                AS DisplayName,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            SUM(COALESCE(p.Score, 0))    AS TotalScore,
            MAX(p.CreationDate)          AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName
    ),
    UserBadges AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    UserTopTags AS (
        SELECT
            up.UserId,
            tag,
            cnt,
            ROW_NUMBER() OVER (PARTITION BY up.UserId ORDER BY cnt DESC) AS rn
        FROM (
            SELECT
                p.OwnerUserId                                 AS UserId,
                TRIM(t)                                       AS tag,
                COUNT(*)                                      AS cnt
            FROM Posts p
            CROSS JOIN LATERAL (
                SELECT regexp_split_to_table(
                           substring(p.Tags FROM 2 FOR char_length(p.Tags)-2),
                           '><'
                       ) AS t
            ) AS split
            WHERE p.OwnerUserId IS NOT NULL
            GROUP BY p.OwnerUserId, tag
        ) up
    ),
    UserVoteScore AS (
        SELECT
            p.OwnerUserId                                 AS UserId,
            SUM(
                CASE vt.Id
                    WHEN 2 THEN 1
                    WHEN 3 THEN -1
                    ELSE 0
                END
            )                                            AS VoteScoreSum
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        JOIN Posts p      ON p.Id = v.PostId
        GROUP BY p.OwnerUserId
    ),
    DistinctVoters AS (
        SELECT
            p.OwnerUserId                                 AS UserId,
            COUNT(DISTINCT v.UserId)                      AS DistinctVoterCount
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE v.UserId IS NOT NULL
        GROUP BY p.OwnerUserId
    )
SELECT
    up.UserId,
    up.DisplayName,
    up.QuestionCount,
    up.AnswerCount,
    up.TotalScore,
    COALESCE(ub.GoldBadges,   0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    tt.tag                               AS TopTag,
    tt.cnt                               AS TopTagUsage,
    RANK() OVER (
        ORDER BY (up.TotalScore
                  + COALESCE(ub.GoldBadges,   0) * 100
                  + COALESCE(ub.SilverBadges, 0) * 50
                  + COALESCE(ub.BronzeBadges, 0) * 10) DESC
    )                                     AS UserRank,
    CASE WHEN up.LastPostDate IS NULL THEN NULL
         ELSE DATE_PART('day', CAST('2024-10-01 12:34:56' AS TIMESTAMP) - up.LastPostDate)
    END                                 AS DaysSinceLastPost,
    COALESCE(dv.DistinctVoterCount, 0)   AS DistinctVoterCount,
    COALESCE(uvs.VoteScoreSum, 0)        AS VoteScoreSum
FROM UserPosts up
LEFT JOIN UserBadges ub
       ON ub.UserId = up.UserId
LEFT JOIN (
    SELECT UserId, tag, cnt
    FROM UserTopTags
    WHERE rn = 1
) tt
       ON tt.UserId = up.UserId
LEFT JOIN UserVoteScore uvs
       ON uvs.UserId = up.UserId
LEFT JOIN DistinctVoters dv
       ON dv.UserId = up.UserId
WHERE up.QuestionCount > 0 OR up.AnswerCount > 0

UNION ALL

SELECT
    u.Id                         AS UserId,
    u.DisplayName                AS DisplayName,
    0                            AS QuestionCount,
    0                            AS AnswerCount,
    0                            AS TotalScore,
    0                            AS GoldBadges,
    0                            AS SilverBadges,
    0                            AS BronzeBadges,
    NULL                         AS TopTag,
    NULL                         AS TopTagUsage,
    NULL                         AS UserRank,
    NULL                         AS DaysSinceLastPost,
    0                            AS DistinctVoterCount,
    0                            AS VoteScoreSum
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY UserRank NULLS LAST, TotalScore DESC
LIMIT 100;