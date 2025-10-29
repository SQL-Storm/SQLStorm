-- {"query": "5000.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2242}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserPostInteraction AS (
    SELECT DISTINCT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation AS UserReputation,
        u.CreationDate AS UserCreationDate,
        CASE
            WHEN SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 0 THEN 'Questioner'
            WHEN SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 0 THEN 'Answerer'
            ELSE 'Other'
        END AS PrimaryRole,
        AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalPostViews,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostsCount,
        MAX(p.LastActivityDate) AS UserLastActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RecentActivity AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS HistoryCreationDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.UserId IS NOT NULL
),
HighEngagementUsers AS (
    SELECT
        upi.UserId,
        upi.UserDisplayName,
        upi.UserReputation,
        upi.TotalPosts,
        upi.AvgPostScore,
        upi.TotalPostViews,
        upi.UserLastActivity,
        CASE
            WHEN upi.TotalPosts > 1000 AND upi.AvgPostScore > 50 THEN 'HighActivityHighScore'
            WHEN upi.TotalPosts > 500 AND upi.UserReputation > 10000 THEN 'HighActivityReputation'
            WHEN upi.UserLastActivity > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') THEN 'RecentlyActive'
            ELSE 'Standard'
        END AS EngagementLevel
    FROM UserPostInteraction upi
    WHERE upi.TotalPosts > 10
),
TaggedPosts AS (
    SELECT
        p.Id AS PostId,
        NULLIF(TRIM(tag), '') AS TagName,
        p.CreationDate AS PostCreationDate,
        p.OwnerUserId
    FROM Posts p,
    LATERAL (
        -- split tags like '<tag1><tag2>' into rows; using generic SQL: replace angle brackets then split on spaces
        -- First replace angle brackets with spaces, then split by whitespace.
        -- Use a regexp-like split implemented via common_table_expression of numbers if needed; here assume a split function SPLIT_PART_ARRAY available.
        -- For portability, implement a simple split by converting to XML and extracting tokens when possible.
        -- Fallback: use a recursive split for space-separated tokens after replacing angle brackets.
        WITH RECURSIVE parts(idx, rest, tag) AS (
            SELECT 1, REGEXP_REPLACE(REPLACE(REPLACE(p.Tags, '<', ' '), '>', ' '), '\s+', ' ', 'g'), NULL
            UNION ALL
            SELECT
                idx + 1,
                CASE
                    WHEN POSITION(' ' IN rest) = 0 THEN ''
                    ELSE LTRIM(SUBSTR(rest, POSITION(' ' IN rest) + 1))
                END,
                CASE
                    WHEN POSITION(' ' IN rest) = 0 THEN rest
                    ELSE SUBSTR(rest, 1, POSITION(' ' IN rest) - 1)
                END
            FROM parts
            WHERE rest <> ''
        )
        SELECT tag FROM parts WHERE tag IS NOT NULL
    ) s(tag)
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
TopTags AS (
    SELECT
        t.TagName,
        COUNT(tp.PostId) AS TagPostCount,
        AVG(CAST(tp.PostCreationDate AS DATE) - CAST(u.CreationDate AS DATE)) AS AvgDaysToFirstTagPost
    FROM Tags t
    JOIN TaggedPosts tp ON t.TagName = tp.TagName
    JOIN Users u ON tp.OwnerUserId = u.Id
    GROUP BY t.TagName
    HAVING COUNT(tp.PostId) > 500
    ORDER BY TagPostCount DESC
    LIMIT 10
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.PostTypeName || ' (' || rp.PostScore || ' score)' AS PostDescription,
    CASE
        WHEN rp.PostScore > 1000 THEN 'HighScore'
        WHEN rp.PostScore < 0 THEN 'NegativeScore'
        ELSE 'StandardScore'
    END AS ScoreCategory,
    CASE
        WHEN rp.PostViewCount IS NULL THEN NULL
        WHEN rp.PostViewCount = 0 THEN 0
        WHEN rp.PostViewCount < 100 THEN 1
        WHEN rp.PostViewCount < 1000 THEN 2
        ELSE 3
    END AS ViewBand,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS UserReputation,
    u.CreationDate AS UserCreationDate,
    hu.EngagementLevel,
    ra.HistoryTypeName AS MostRecentHistoryAction,
    ra.HistoryCreationDate AS MostRecentHistoryDate,
    tt.TagName AS TopTagAssociated,
    CASE
        WHEN rp.ClosedDate IS NOT NULL AND rp.ClosedDate < rp.PostCreationDate + INTERVAL '1 year' THEN 'RecentlyClosed'
        WHEN rp.ClosedDate IS NOT NULL THEN 'LongAgoClosed'
        ELSE 'NeverClosed'
    END AS ClosureStatus,
    COALESCE(rp.FavoriteCount, 0) + COALESCE(rp.AnswerCount, 0) AS EngagementMetric,
    LOWER(rp.PostTypeName) AS LowerPostType,
    LENGTH(rp.PostTypeName) AS PostTypeNameLength,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    CASE WHEN tt.TagName IS NOT NULL THEN 'HasTopTag' ELSE 'NoTopTag' END AS TopTagPresence,
    (rp.PostScore * 1.0 / NULLIF(rp.PostViewCount, 0)) AS ScoreToViewRatio,
    rp.PostCreationDate + (INTERVAL '1 day' * rp.rn) AS HypotheticalFutureDate,
    rp.rn
FROM RankedPosts rp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN HighEngagementUsers hu ON u.Id = hu.UserId
LEFT JOIN RecentActivity ra ON rp.PostId = ra.PostId AND ra.rn = 1
LEFT JOIN TaggedPosts tp ON rp.PostId = tp.PostId
LEFT JOIN TopTags tt ON tp.TagName = tt.TagName
WHERE rp.rn <= 100
    AND LENGTH(u.DisplayName) > 3
    AND UPPER(u.DisplayName) NOT LIKE '%BOT%'
    AND rp.PostTypeId IN (1, 2)
    AND rp.PostScore BETWEEN -10 AND 1000
    AND rp.PostCreationDate >= DATE '2023-01-01'
    AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = rp.PostId AND c.Score > 5)
UNION
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.PostTypeName || ' (' || rp.PostScore || ' score)' AS PostDescription,
    CASE
        WHEN rp.PostScore > 1000 THEN 'HighScore'
        WHEN rp.PostScore < 0 THEN 'NegativeScore'
        ELSE 'StandardScore'
    END AS ScoreCategory,
    CASE
        WHEN rp.PostViewCount IS NULL THEN NULL
        WHEN rp.PostViewCount = 0 THEN 0
        WHEN rp.PostViewCount < 100 THEN 1
        WHEN rp.PostViewCount < 1000 THEN 2
        ELSE 3
    END AS ViewBand,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS UserReputation,
    u.CreationDate AS UserCreationDate,
    hu.EngagementLevel,
    ra.HistoryTypeName AS MostRecentHistoryAction,
    ra.HistoryCreationDate AS MostRecentHistoryDate,
    tt.TagName AS TopTagAssociated,
    CASE
        WHEN rp.ClosedDate IS NOT NULL AND rp.ClosedDate < rp.PostCreationDate + INTERVAL '1 year' THEN 'RecentlyClosed'
        WHEN rp.ClosedDate IS NOT NULL THEN 'LongAgoClosed'
        ELSE 'NeverClosed'
    END AS ClosureStatus,
    COALESCE(rp.FavoriteCount, 0) + COALESCE(rp.AnswerCount, 0) AS EngagementMetric,
    LOWER(rp.PostTypeName) AS LowerPostType,
    LENGTH(rp.PostTypeName) AS PostTypeNameLength,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    CASE WHEN tt.TagName IS NOT NULL THEN 'HasTopTag' ELSE 'NoTopTag' END AS TopTagPresence,
    (rp.PostScore * 1.0 / NULLIF(rp.PostViewCount, 0)) AS ScoreToViewRatio,
    rp.PostCreationDate + (INTERVAL '1 day' * rp.rn) AS HypotheticalFutureDate,
    rp.rn
FROM RankedPosts rp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN HighEngagementUsers hu ON u.Id = hu.UserId
LEFT JOIN RecentActivity ra ON rp.PostId = ra.PostId AND ra.rn = 1
LEFT JOIN TaggedPosts tp ON rp.PostId = tp.PostId
LEFT JOIN TopTags tt ON tp.TagName = tt.TagName
WHERE rp.rn <= 50
    AND LENGTH(u.DisplayName) <= 3
    AND rp.PostTypeId IN (3, 5)
    AND rp.PostScore >= 0
    AND rp.PostCreationDate >= DATE '2022-01-01'
    AND NOT EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = rp.PostId AND c.Score > 0)
ORDER BY PostScore DESC
LIMIT 100;