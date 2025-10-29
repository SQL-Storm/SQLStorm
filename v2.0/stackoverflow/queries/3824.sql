WITH
    BadgeAgg AS (
        SELECT
            b.UserId,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
            COUNT(*)                                 AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),

    PostAgg AS (
        SELECT
            p.OwnerUserId               AS UserId,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
            SUM(p.Score)                AS ScoreSum,
            AVG(p.Score)                AS ScoreAvg,
            MAX(p.CreationDate)         AS LastPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    TagExplode AS (
        SELECT
            p.OwnerUserId AS UserId,
            UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
        FROM Posts p
        WHERE p.Tags IS NOT NULL
    ),

    TagCount AS (
        SELECT
            te.UserId,
            te.Tag,
            COUNT(*)                                     AS TagUses,
            ROW_NUMBER() OVER (PARTITION BY te.UserId ORDER BY COUNT(*) DESC) AS rn
        FROM TagExplode te
        GROUP BY te.UserId, te.Tag
    ),

    TopTag AS (
        SELECT UserId, Tag, TagUses
        FROM TagCount
        WHERE rn = 1
    ),

    RecentVote AS (
        SELECT
            v.PostId,
            v.UserId,
            v.VoteTypeId,
            v.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
        FROM Votes v
    ),
    LatestVotePerPost AS (
        SELECT PostId, UserId AS VoterId, VoteTypeId, CreationDate
        FROM RecentVote
        WHERE rn = 1
    ),

    UserActivity AS (
        SELECT
            u.Id AS UserId,
            GREATEST(
                COALESCE(u.LastAccessDate,      TIMESTAMP '1970-01-01'),
                COALESCE(p.LastPostDate,       TIMESTAMP '1970-01-01'),
                COALESCE(v.CreationDate,       TIMESTAMP '1970-01-01')
            ) AS LastActivity
        FROM Users u
        LEFT JOIN PostAgg p   ON u.Id = p.UserId
        LEFT JOIN LatestVotePerPost v ON u.Id = v.VoterId
    ),

    CompositeScore AS (
        SELECT
            u.Id                                            AS UserId,
            u.Reputation,
            COALESCE(b.TotalBadges,0)                       AS TotalBadges,
            COALESCE(p.ScoreSum,0)                          AS TotalPostScore,
            COALESCE(p.Answers,0) * 2 + COALESCE(p.Questions,0) AS EngagementWeight,
            COALESCE(t.TagUses,0)                           AS TopTagUsage,
            ROW_NUMBER() OVER (
                ORDER BY
                    (u.Reputation      * 0.4) +
                    (COALESCE(b.TotalBadges,0) * 10) +
                    (COALESCE(p.ScoreSum,0)     * 0.2) +
                    (COALESCE(p.Answers,0)      * 5) +
                    (COALESCE(t.TagUses,0)      * 1) DESC
            )                                             AS Rank
        FROM Users u
        LEFT JOIN BadgeAgg b   ON u.Id = b.UserId
        LEFT JOIN PostAgg p    ON u.Id = p.UserId
        LEFT JOIN TopTag t     ON u.Id = t.UserId
    ),

    FinalSet AS (
        SELECT
            cs.UserId,
            u.DisplayName,
            cs.Rank,
            cs.Reputation,
            cs.TotalBadges,
            cs.TotalPostScore,
            cs.TopTagUsage,
            COALESCE(t.Tag, 'N/A')          AS TopTag,
            ua.LastActivity,
            CASE
                WHEN cs.Rank <= 10  THEN 'Elite'
                WHEN cs.Rank <= 100 THEN 'Pro'
                ELSE 'Member'
            END                              AS Tier,
            ('User ' || COALESCE(u.DisplayName,'Anonymous') || ' is ranked ' || CAST(cs.Rank AS VARCHAR)) AS Summary
        FROM CompositeScore cs
        JOIN Users u          ON cs.UserId = u.Id
        LEFT JOIN TopTag t    ON cs.UserId = t.UserId
        LEFT JOIN UserActivity ua ON cs.UserId = ua.UserId
        WHERE cs.Rank <= 200
    )

SELECT *
FROM (
    SELECT *
    FROM FinalSet
    UNION ALL
    SELECT
        NULL      AS UserId,
        NULL      AS DisplayName,
        NULL      AS Rank,
        NULL      AS Reputation,
        NULL      AS TotalBadges,
        NULL      AS TotalPostScore,
        NULL      AS TopTagUsage,
        '---'     AS TopTag,
        NULL      AS LastActivity,
        'Footer'  AS Tier,
        'End of report' AS Summary
) AS combined
ORDER BY
    (Rank IS NULL) ASC,
    Rank ASC;