WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        u.CreationDate AS OwnerCreationDate,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM
        Posts p
    JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 day'
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, pt.Name, u.DisplayName, u.Reputation, u.CreationDate
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.OwnerCreationDate,
    rp.CommentCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownVoteCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS DuplicateLinkCount
FROM
    RankedPosts rp
WHERE
    rp.rn <= 100
ORDER BY
    rp.rn;