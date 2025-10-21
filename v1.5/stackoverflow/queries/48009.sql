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
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as rn
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
        AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 days')
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
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = rp.PostId AND PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
    (SELECT COUNT(*) FROM Votes WHERE PostId = rp.PostId AND VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Votes WHERE PostId = rp.PostId AND VoteTypeId = 3) AS DownVoteCount,
    (SELECT COUNT(*) FROM PostLinks WHERE PostId = rp.PostId AND LinkTypeId = 3) AS DuplicateLinkCount
FROM
    RankedPosts rp
WHERE
    rp.rn <= 100
ORDER BY
    rp.rn;