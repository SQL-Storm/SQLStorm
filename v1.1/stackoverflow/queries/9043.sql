WITH
RecentActivity AS (
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        COALESCE(
            COUNT(p.Id) FILTER (WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'),
            0
        )             AS PostsLast30,
        COALESCE(
            SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId IN (8,9)),
            0
        )             AS TotalBounty
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName
),
TagFrequency AS (
    SELECT
        t.TagName,
        COUNT(*)                AS UsageCount,
        ROW_NUMBER() OVER (
            ORDER BY COUNT(*) DESC
        )                       AS TagRank
    FROM Posts p,
    LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '><')) AS TagName
    ) t
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
HighActivity AS (
    SELECT
        ra.UserId,
        ra.DisplayName,
        ra.PostsLast30,
        ra.TotalBounty,
        tf.UsageCount,
        tf.TagRank
    FROM RecentActivity ra
    LEFT JOIN TagFrequency tf
      ON tf.TagRank <= 10
),
DupCountPerPost AS (
    SELECT
        pl.PostId,
        COUNT(*) AS DupCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
HighScoreAnswers AS (
    SELECT
        u.Id                     AS UserId,
        (
            SELECT COUNT(*)
            FROM Posts p2
            WHERE
                p2.OwnerUserId = u.Id
                AND p2.PostTypeId = 2
                AND p2.Score > COALESCE(ra.TotalBounty,0) / NULLIF(ra.PostsLast30, 0)
        )                       AS HighScoreAnswerCount
    FROM Users u
    LEFT JOIN RecentActivity ra ON ra.UserId = u.Id
),
ActivityWithDups AS (
    SELECT
        ha.UserId,
        ha.DisplayName,
        ha.PostsLast30,
        ha.TotalBounty,
        ha.UsageCount      AS TopTagUses,
        ha.TagRank         AS TopTagRank,
        dc.DupCount        AS PostDuplicates,
        hs.HighScoreAnswerCount
    FROM HighActivity ha
    FULL OUTER JOIN DupCountPerPost dc
      ON dc.PostId = ha.UserId
    LEFT JOIN HighScoreAnswers hs
      ON hs.UserId = ha.UserId
)
SELECT
    awd.UserId,
    awd.DisplayName,
    length(COALESCE(awd.DisplayName,''))       AS NameLength,
    (COALESCE(awd.DisplayName,'') || '_' || CAST(awd.UserId AS VARCHAR))     AS UserKey,
    awd.PostsLast30,
    awd.TotalBounty,
    awd.TopTagUses,
    awd.TopTagRank,
    awd.PostDuplicates,
    awd.HighScoreAnswerCount,
    NULLIF(awd.DisplayName,'')                 AS CleanDisplayName,
    LAG(awd.PostDuplicates) OVER (
        ORDER BY awd.TotalBounty DESC
    )                                           AS PrevUserDupCount
FROM ActivityWithDups awd
WHERE
    (
        awd.PostsLast30 > 5
        AND awd.PostDuplicates IS NULL
    )
    OR
    (
        awd.TotalBounty > 100
        AND awd.PostDuplicates > 2
    )
EXCEPT
SELECT
    u.Id,
    u.DisplayName,
    length(COALESCE(u.DisplayName,''))       AS NameLength,
    (COALESCE(u.DisplayName,'') || '_' || CAST(u.Id AS VARCHAR))     AS UserKey,
    CAST(0 AS BIGINT),            -- PostsLast30
    CAST(0 AS NUMERIC),           -- TotalBounty
    CAST(0 AS BIGINT),            -- TopTagUses
    CAST(0 AS BIGINT),            -- TopTagRank
    CAST(0 AS BIGINT),            -- PostDuplicates
    CAST(NULL AS BIGINT),         -- HighScoreAnswerCount
    NULLIF(u.DisplayName,'')                 AS CleanDisplayName,
    CAST(NULL AS BIGINT)          -- PrevUserDupCount
FROM Users u;