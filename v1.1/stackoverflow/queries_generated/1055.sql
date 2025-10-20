-- {"query": "1055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 432} 

WITH UserVoteSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(v.Id) AS TotalVotes,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY 
        u.Id
),
TopPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '30 days'
    AND 
        p.Score > 0
),
PostCommentCounts AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount
    FROM 
        Comments c
    GROUP BY 
        c.PostId
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    pp.PostId,
    pp.Title,
    pp.Score,
    pp.ViewCount,
    COALESCE(pcc.CommentCount, 0) AS CommentCount,
    CASE 
        WHEN ups.UpVotes > ups.DownVotes THEN 'Positive'
        WHEN ups.UpVotes < ups.DownVotes THEN 'Negative'
        ELSE 'Neutral'
    END AS UserVoteSentiment
FROM 
    UserVoteSummary ups
JOIN 
    TopPosts pp ON ups.TotalVotes > 5
LEFT JOIN 
    PostCommentCounts pcc ON pp.PostId = pcc.PostId
WHERE 
    pp.Rank <= 10
AND 
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pp.PostId AND v.UserId = ups.UserId) > 0
ORDER BY 
    ups.TotalVotes DESC, pp.Score DESC;
