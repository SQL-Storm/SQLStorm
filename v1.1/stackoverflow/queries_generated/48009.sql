-- {"query": "48009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 562} 

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
        p.PostTypeId = 1 -- Only consider questions
        AND p.CreationDate >= DATE('now', '-365 day') -- Posts created in the last year
        AND p.OwnerUserId IS NOT NULL -- Exclude posts owned by deleted users
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
    (SELECT COUNT(*) FROM PostHistory WHERE PostId = rp.PostId AND PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount, -- Count of edits (title, body, tags)
    (SELECT COUNT(*) FROM Votes WHERE PostId = rp.PostId AND VoteTypeId = 2) AS UpVoteCount, -- Count of upvotes
    (SELECT COUNT(*) FROM Votes WHERE PostId = rp.PostId AND VoteTypeId = 3) AS DownVoteCount, -- Count of downvotes
    (SELECT COUNT(*) FROM PostLinks WHERE PostId = rp.PostId AND LinkTypeId = 3) AS DuplicateLinkCount -- Count of duplicate links pointing to this post
FROM
    RankedPosts rp
WHERE
    rp.rn <= 100 -- Limit to top 100 ranked posts
ORDER BY
    rp.rn;
