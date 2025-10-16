WITH TopUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighScorePosts AS (
    SELECT p.Id AS PostId, p.OwnerUserId, p.CreationDate, (p.Score + COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)) AS EffectiveScore
    FROM Posts p
    LEFT JOIN (
        SELECT vt.PostId,
               SUM(CASE WHEN vt.Id = 2 THEN 1 WHEN vt.Id = 3 THEN -1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes vt
        GROUP BY vt.PostId
    ) v ON v.PostId = p.Id
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year' AND p.Score > 10
),
CombinedData AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.BadgeCount,
        hp.PostId,
        hp.CreationDate,
        hp.EffectiveScore,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY hp.EffectiveScore DESC) AS Rank
    FROM TopUsers tu
    JOIN HighScorePosts hp ON tu.UserId = hp.OwnerUserId
),
PostTags AS (
    /* Expand post tag strings like '<tag1><tag2>' into one row per tag */
    SELECT
        p.Id AS PostId,
        -- remove leading/trailing angle brackets
        REGEXP_REPLACE(p.Tags, '^<|>$', '', 'g') AS TagsStr
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
ExplodedTags AS (
    SELECT
        pt.PostId,
        -- generate positions 1..number_of_tags; use standard SQL GENERATE_SERIES if available, otherwise emulate with a numbers table
        gs.i,
        -- extract the i-th tag from the string of tags using standard functions
        -- SPLIT_PART is available in many dialects (Postgres). For portability, keep SPLIT_PART; if not available replace with equivalent.
        SPLIT_PART(pt.TagsStr, '><', gs.i) AS TagName
    FROM PostTags pt
    JOIN (
        -- generate series from 1 to max number of tags per post; here we approximate using a numbers CTE
        SELECT 1 AS i UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
        -- extend as needed for more tags
    ) gs ON gs.i <= 1 + LENGTH(pt.TagsStr) - LENGTH(REPLACE(pt.TagsStr, '<', ''))
)
SELECT 
    cd.UserId,
    cd.DisplayName,
    cd.BadgeCount,
    STRING_AGG(et.TagName, ', ') AS AssociatedTags,
    SUM(cd.EffectiveScore) AS TotalEffectiveScore
FROM CombinedData cd
LEFT JOIN ExplodedTags et ON et.PostId = cd.PostId
WHERE cd.Rank <= 5
GROUP BY cd.UserId, cd.DisplayName, cd.BadgeCount
HAVING COUNT(et.TagName) > 0;