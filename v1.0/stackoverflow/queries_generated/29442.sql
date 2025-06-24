WITH RankedPosts AS (
    SELECT 
        p.Title,
        p.Body,
        p.CreationDate,
        u.DisplayName AS Author,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 -- Only questions
    GROUP BY p.Id, p.Title, p.Body, p.CreationDate, u.DisplayName
),

FilteredPosts AS (
    SELECT 
        r.Title,
        r.Body,
        r.CreationDate,
        r.Author,
        r.CommentCount,
        r.UpVotes,
        r.DownVotes
    FROM RankedPosts r
    WHERE r.rn = 1 -- Get the latest version of each post
    ORDER BY r.UpVotes DESC, r.CommentCount DESC
)

SELECT 
    fp.Title, 
    fp.Body, 
    fp.CreationDate, 
    fp.Author, 
    fp.CommentCount, 
    fp.UpVotes, 
    fp.DownVotes,
    (fp.UpVotes - fp.DownVotes) AS Score,
    CASE 
        WHEN fp.UpVotes > 100 THEN 'Hot'
        WHEN fp.UpVotes BETWEEN 50 AND 100 THEN 'Trending'
        ELSE 'Normal'
    END AS Popularity
FROM FilteredPosts fp
WHERE fp.UpVotes >= 10 -- Only considering popular questions
LIMIT 10;

-- This query provides a list of the 10 most popular questions based on upvotes 
-- and displays additional information like comment count and a computed score 
-- with popularity classifications for string processing benchmarking.
