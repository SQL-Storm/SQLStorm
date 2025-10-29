WITH
BadgeAgg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
LatestPost AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.CreationDate DESC
        ) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
UserLatestPost AS (
    SELECT *
    FROM LatestPost
    WHERE rn = 1
),
VoteAgg AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(v.Id) AS TotalVotesReceived
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TagUsage AS (
    SELECT
        p.OwnerUserId AS UserId,
        -- replace UNNEST(regexp_split_to_array(...)) with standard string_split equivalent where available.
        -- Use regexp_split_to_table for broad compatibility; many DBs support similar functions, but keep as a derived table.
        t.TagName,
        COUNT(*) AS TagAppearances
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(regexp_replace(p.Tags, '^<|>$', '', 'g'), '><') AS TagName
    ) t
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
TopTagPerUser AS (
    SELECT
        tu.UserId,
        tu.TagName,
        tu.TagAppearances,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.TagAppearances DESC) AS rn
    FROM TagUsage tu
),
UserTopTag AS (
    SELECT UserId, TagName, TagAppearances
    FROM TopTagPerUser
    WHERE rn = 1
),
DuplicateLinks AS (
    SELECT
        pl.PostId AS DuplicatePostId,
        pl.RelatedPostId AS OriginalPostId,
        pl.CreationDate AS LinkDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
),
InactiveUsers AS (
    SELECT u.Id AS UserId
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '2 years')
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '2 years')
    WHERE p.Id IS NULL
      AND c.Id IS NULL
),
UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(v.UpVotesReceived, 0) AS UpVotesReceived,
        COALESCE(v.DownVotesReceived, 0) AS DownVotesReceived,
        COALESCE(v.TotalVotesReceived, 0) AS TotalVotesReceived,
        COALESCE(p.Title, '<no posts>') AS LatestPostTitle,
        COALESCE(p.Score, 0) AS LatestPostScore,
        COALESCE(p.CreationDate, TIMESTAMP '1970-01-01') AS LatestPostDate,
        COALESCE(t.TagName, '<none>') AS TopTag,
        COALESCE(t.TagAppearances, 0) AS TopTagUsage,
        CASE WHEN i.UserId IS NOT NULL THEN 1 ELSE 0 END AS IsInactive
    FROM Users u
    LEFT JOIN BadgeAgg b ON b.UserId = u.Id
    LEFT JOIN VoteAgg v ON v.UserId = u.Id
    LEFT JOIN UserLatestPost p ON p.UserId = u.Id
    LEFT JOIN UserTopTag t ON t.UserId = u.Id
    LEFT JOIN InactiveUsers i ON i.UserId = u.Id
)

SELECT *
FROM (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        UpVotesReceived,
        DownVotesReceived,
        TotalVotesReceived,
        LatestPostTitle,
        LatestPostScore,
        LatestPostDate,
        TopTag,
        TopTagUsage,
        IsInactive
    FROM UserStats
    WHERE Reputation > 10000
    ORDER BY Reputation DESC
    LIMIT 100
) u

UNION ALL

SELECT
    CAST(NULL AS INTEGER) AS UserId,
    'Tag Summary' AS DisplayName,
    CAST(NULL AS INTEGER) AS Reputation,
    CAST(NULL AS INTEGER) AS GoldBadges,
    CAST(NULL AS INTEGER) AS SilverBadges,
    CAST(NULL AS INTEGER) AS BronzeBadges,
    CAST(NULL AS INTEGER) AS UpVotesReceived,
    CAST(NULL AS INTEGER) AS DownVotesReceived,
    CAST(NULL AS INTEGER) AS TotalVotesReceived,
    CAST(NULL AS text) AS LatestPostTitle,
    CAST(NULL AS INTEGER) AS LatestPostScore,
    CAST(NULL AS TIMESTAMP) AS LatestPostDate,
    tg.TagName AS TopTag,
    tg.TotalAppearances AS TopTagUsage,
    0 AS IsInactive
FROM (
    SELECT
        tu.TagName,
        SUM(tu.TagAppearances) AS TotalAppearances
    FROM TagUsage tu
    JOIN Users u2 ON u2.Id = tu.UserId
    WHERE u2.Reputation > 10000
    GROUP BY tu.TagName
) tg
ORDER BY TopTagUsage DESC
LIMIT 10;