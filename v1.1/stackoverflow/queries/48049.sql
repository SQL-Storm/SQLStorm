WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        pt.Name AS PostType,
        ROW_NUMBER() OVER (PARTITION BY pt.Name ORDER BY p.ViewCount DESC) AS rn_views,
        ROW_NUMBER() OVER (PARTITION BY pt.Name ORDER BY p.Score DESC) AS rn_score
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
),
Top10ByView AS (
    SELECT PostId, Title, CreationDate, Score, ViewCount, PostType
    FROM RankedPosts
    WHERE rn_views <= 10
),
Top10ByScore AS (
    SELECT PostId, Title, CreationDate, Score, ViewCount, PostType
    FROM RankedPosts
    WHERE rn_score <= 10
)
SELECT
    'Top 10 by Views' AS Category,
    t10v.PostId,
    t10v.Title,
    t10v.CreationDate,
    t10v.Score,
    t10v.ViewCount,
    t10v.PostType
FROM Top10ByView t10v
UNION ALL
SELECT
    'Top 10 by Score' AS Category,
    t10s.PostId,
    t10s.Title,
    t10s.CreationDate,
    t10s.Score,
    t10s.ViewCount,
    t10s.PostType
FROM Top10ByScore t10s
ORDER BY Category, PostType, ViewCount DESC;