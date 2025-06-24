WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1 -- Only Questions
        AND p.CreationDate > NOW() - INTERVAL '1 year' -- Questions created in the last year
)
SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    ARRAY_AGG(DISTINCT t.TagName) AS AssociatedTags,
    CHANGES.Comment AS LastEditComment,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes
FROM
    RankedPosts rp
LEFT JOIN
    Tags t ON rp.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN
    PostHistory ch ON rp.PostId = ch.PostId
LEFT JOIN
    Votes v ON rp.PostId = v.PostId
WHERE
    rp.Rank <= 5 -- Get Top 5 posts per tag
GROUP BY
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    CHANGES.Comment
ORDER BY
    rp.Score DESC, rp.ViewCount DESC;
