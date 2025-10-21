WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COALESCE(u.DisplayName, 'Community User') AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM
        Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
        AND p.PostTypeId = 1
    GROUP BY
        p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, COALESCE(u.DisplayName, 'Community User'), p.OwnerUserId
), TopRankedPosts AS (
    SELECT
        *,
        RANK() OVER (ORDER BY Score DESC, ViewCount DESC) AS OverallRank
    FROM
        RankedPosts
    WHERE
        Rank <= 5
)
SELECT
    trp.PostId,
    trp.Title,
    trp.Score,
    trp.ViewCount,
    trp.CreationDate,
    trp.OwnerDisplayName,
    trp.CommentCount,
    trp.TotalUpvotes,
    trp.TotalDownvotes,
    trp.OverallRank
FROM
    TopRankedPosts trp
ORDER BY
    trp.OverallRank;