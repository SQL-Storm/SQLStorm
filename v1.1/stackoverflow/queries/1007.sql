WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        COALESCE(v.UpVotes, 0) AS UpVotes,
        COALESCE(v.DownVotes, 0) AS DownVotes,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY MAX(c.CreationDate) DESC) AS LatestCommentRank
    FROM 
        Posts p
    LEFT JOIN (
        SELECT 
            PostId, 
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM 
            Votes
        GROUP BY 
            PostId
    ) v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1' YEAR
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, v.UpVotes, v.DownVotes
), 
TopPosts AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.CreationDate,
        ps.ViewCount,
        ps.UpVotes,
        ps.DownVotes,
        ps.CommentCount,
        ps.LatestCommentRank,
        (ps.UpVotes - ps.DownVotes) AS NetScore,
        RANK() OVER (ORDER BY (ps.UpVotes - ps.DownVotes) DESC) AS ScoreRank
    FROM 
        PostStats ps
    WHERE 
        ps.LatestCommentRank = 1
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.ViewCount,
    tp.UpVotes,
    tp.DownVotes,
    tp.CommentCount,
    tp.NetScore,
    CASE 
        WHEN tp.NetScore > 100 THEN 'Hot'
        WHEN tp.NetScore BETWEEN 50 AND 100 THEN 'Trending'
        ELSE 'Normal'
    END AS PostStatus
FROM 
    TopPosts tp
WHERE 
    tp.ScoreRank <= 10
ORDER BY 
    tp.NetScore DESC;