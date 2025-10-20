WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.LastActivityDate,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount,
        p.PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRank
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
    GROUP BY
        p.Id, u.DisplayName, p.CreationDate, p.LastActivityDate, p.Score, p.Title, p.PostTypeId
),
TopPosts AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.OwnerDisplayName,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.CommentCount,
        rp.UpVoteCount,
        rp.DownVoteCount,
        rp.PostTypeId,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY rp.PostTypeId ORDER BY rp.Score DESC) AS OverallRank
    FROM
        RankedPosts rp
    JOIN
        PostTypes pt ON rp.PostTypeId = pt.Id
)
SELECT
    tp.PostId,
    tp.Title,
    tp.OwnerDisplayName,
    tp.Score,
    tp.CommentCount,
    tp.UpVoteCount,
    tp.DownVoteCount,
    tp.CreationDate,
    tp.LastActivityDate,
    tp.PostTypeName,
    tp.PostTypeId
FROM
    TopPosts tp
WHERE
    tp.OverallRank <= 10
ORDER BY
    tp.PostTypeId, tp.Score DESC;