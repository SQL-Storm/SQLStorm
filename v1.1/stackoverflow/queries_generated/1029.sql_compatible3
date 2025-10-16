WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn,
        COALESCE(SUM(CASE WHEN vt.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN vt.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id), 0) AS DownVotes,
        CAST(NULL AS INTEGER) AS CommentCount,
        CAST(NULL AS TEXT) AS Tags
    FROM 
        Posts p
    LEFT JOIN 
        Votes vt ON p.Id = vt.PostId
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
PostComments AS (
    SELECT
        c.PostId AS Id,
        COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
),
PostTags AS (
    SELECT
        p2.Id AS Id,
        STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM t), ', ') AS Tags
    FROM Posts p2
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(p2.Tags, '><')) AS t
    ) u
    GROUP BY p2.Id
),
RankedPostsAgg AS (
    SELECT
        rp.Id,
        rp.Title,
        rp.ViewCount,
        rp.Score,
        rp.rn,
        rp.UpVotes,
        rp.DownVotes,
        COALESCE(pc.CommentCount, 0) AS CommentCount,
        COALESCE(pt.Tags, '') AS Tags
    FROM RankedPosts rp
    LEFT JOIN PostComments pc ON pc.Id = rp.Id
    LEFT JOIN PostTags pt ON pt.Id = rp.Id
),
ClosedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        ph.CreationDate AS ClosedDate,
        ph.UserDisplayName AS ClosedBy,
        ph.Comment AS CloseReason
    FROM 
        Posts p
    JOIN 
        PostHistory ph ON p.Id = ph.PostId
    WHERE 
        ph.PostHistoryTypeId = 10 
        AND ph.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
)
SELECT 
    rp.Title,
    rp.ViewCount,
    rp.Score,
    rp.UpVotes,
    rp.DownVotes,
    rp.CommentCount,
    rp.Tags,
    cp.ClosedDate,
    cp.ClosedBy,
    cp.CloseReason
FROM 
    RankedPostsAgg rp
LEFT JOIN 
    ClosedPosts cp ON rp.Id = cp.Id
WHERE 
    rp.rn = 1 OR cp.ClosedDate IS NOT NULL
GROUP BY
    rp.Id,
    rp.Title,
    rp.ViewCount,
    rp.Score,
    rp.UpVotes,
    rp.DownVotes,
    rp.CommentCount,
    rp.Tags,
    cp.ClosedDate,
    cp.ClosedBy,
    cp.CloseReason,
    rp.rn
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC;