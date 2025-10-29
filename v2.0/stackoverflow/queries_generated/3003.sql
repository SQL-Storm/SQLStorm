-- {"query": "3003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1616} 

/*  Complex benchmark query over the StackOverflow schema  */
WITH
/* -------------------------------------------------------------
   1. Aggregate badge counts per user, pivoted by class
   ------------------------------------------------------------- */
BadgeAgg AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*)                                          AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),

/* -------------------------------------------------------------
   2. Latest post (question or answer) per user with a window fn
   ------------------------------------------------------------- */
LatestPost AS (
    SELECT
        p.OwnerUserId               AS UserId,
        p.Id                        AS PostId,
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

/* -------------------------------------------------------------
   3. Vote summary per user (upvotes/downvotes) with NULL handling
   ------------------------------------------------------------- */
VoteAgg AS (
    SELECT
        p.OwnerUserId                         AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(v.Id)                                        AS TotalVotesReceived
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* -------------------------------------------------------------
   4. Tag statistics for tags used by a user's questions
   ------------------------------------------------------------- */
TagUsage AS (
    SELECT
        p.OwnerUserId                           AS UserId,
        UNNEST(                                   -- split <tag1><tag2>… format
            regexp_split_to_array(
                regexp_replace(p.Tags, '^<|>$', '', 'g'),
                '><'
            )
        ) AS TagName,
        COUNT(*)                                 AS TagAppearances
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- only questions
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, TagName
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

/* -------------------------------------------------------------
   5. Duplicate link analysis (posts that are marked duplicate)
   ------------------------------------------------------------- */
DuplicateLinks AS (
    SELECT
        pl.PostId          AS DuplicatePostId,
        pl.RelatedPostId   AS OriginalPostId,
        pl.CreationDate    AS LinkDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
),

/* -------------------------------------------------------------
   6. Users with no activity in the last 2 years (outer join test)
   ------------------------------------------------------------- */
InactiveUsers AS (
    SELECT u.Id AS UserId
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate > (CURRENT_DATE - INTERVAL '2 years')
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate > (CURRENT_DATE - INTERVAL '2 years')
    WHERE p.Id IS NULL
      AND c.Id IS NULL
),

/* -------------------------------------------------------------
   7. Combined user statistics
   ------------------------------------------------------------- */
UserStats AS (
    SELECT
        u.Id                                   AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.GoldBadges,0)               AS GoldBadges,
        COALESCE(b.SilverBadges,0)             AS SilverBadges,
        COALESCE(b.BronzeBadges,0)             AS BronzeBadges,
        COALESCE(v.UpVotesReceived,0)          AS UpVotesReceived,
        COALESCE(v.DownVotesReceived,0)        AS DownVotesReceived,
        COALESCE(v.TotalVotesReceived,0)       AS TotalVotesReceived,
        COALESCE(p.Title, '<no posts>')        AS LatestPostTitle,
        COALESCE(p.Score,0)                    AS LatestPostScore,
        COALESCE(p.CreationDate, TIMESTAMP '1970-01-01') AS LatestPostDate,
        COALESCE(t.TagName,'<none>')           AS TopTag,
        COALESCE(t.TagAppearances,0)           AS TopTagUsage,
        CASE WHEN i.UserId IS NOT NULL THEN 1 ELSE 0 END AS IsInactive
    FROM Users u
    LEFT JOIN BadgeAgg b      ON b.UserId = u.Id
    LEFT JOIN VoteAgg v       ON v.UserId = u.Id
    LEFT JOIN UserLatestPost p ON p.UserId = u.Id
    LEFT JOIN UserTopTag t    ON t.UserId = u.Id
    LEFT JOIN InactiveUsers i ON i.UserId = u.Id
)

/* -------------------------------------------------------------
   Final SELECT with UNION ALL to add a summary row set
   ------------------------------------------------------------- */
SELECT *
FROM UserStats
WHERE Reputation > 10000
ORDER BY Reputation DESC
LIMIT 100

UNION ALL

/* Summary of top tags across all high‑rep users */
SELECT
    NULL                AS UserId,
    'Tag Summary'       AS DisplayName,
    NULL                AS Reputation,
    NULL                AS GoldBadges,
    NULL                AS SilverBadges,
    NULL                AS BronzeBadges,
    NULL                AS UpVotesReceived,
    NULL                AS DownVotesReceived,
    NULL                AS TotalVotesReceived,
    NULL                AS LatestPostTitle,
    NULL                AS LatestPostScore,
    NULL                AS LatestPostDate,
    tg.TagName,
    tg.TotalAppearances,
    0                  AS IsInactive
FROM (
    SELECT
        tu.TagName,
        SUM(tu.TagAppearances) AS TotalAppearances
    FROM TagUsage tu
    JOIN Users u ON u.Id = tu.UserId
    WHERE u.Reputation > 10000
    GROUP BY tu.TagName
) tg
ORDER BY TotalAppearances DESC
LIMIT 10;
