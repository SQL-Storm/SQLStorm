WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Body,
        p.Tags,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount, -- counting upvotes
        COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount, -- counting downvotes
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.CreationDate >= NOW() - INTERVAL '1 year' -- considering only posts created in the last year
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.Body, p.Tags
),
FilteredPosts AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Body,
        rp.Tags,
        rp.CommentCount,
        rp.UpVoteCount,
        rp.DownVoteCount
    FROM
        RankedPosts rp
    WHERE
        rp.rn = 1 -- ensuring we only get the latest entry per post
)
SELECT
    fp.PostId,
    fp.Title,
    fp.CreationDate,
    fp.CommentCount,
    fp.UpVoteCount,
    fp.DownVoteCount,
    (fp.UpVoteCount - fp.DownVoteCount) AS NetVoteScore,
    ARRAY_LENGTH(string_to_array(fp.Tags, '><'), 1) AS TagCount,
    CASE
        WHEN fp.UpVoteCount > fp.DownVoteCount THEN 'Positive'
        WHEN fp.UpVoteCount < fp.DownVoteCount THEN 'Negative'
        ELSE 'Neutral'
    END AS VoteSentiment
FROM
    FilteredPosts fp
ORDER BY
    NetVoteScore DESC
LIMIT 50; -- getting the top 50 posts based on net vote score
