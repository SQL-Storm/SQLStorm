-- {"query": "56011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 469} 
WITH top_users AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes, 
        COUNT(DISTINCT p.Id) AS PostCount
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
top_posts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.Tags, 
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes, 
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVotes
    FROM 
        Posts p
    JOIN 
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, p.Tags
    HAVING 
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) > 5
),
badges AS (
    SELECT 
        b.UserId, 
        b.Name, 
        b.Class
    FROM 
        Badges b
    WHERE 
        b.Class = 1
)
SELECT 
    tu.DisplayName, 
    tu.UpVotes, 
    tu.DownVotes, 
    tu.PostCount, 
    tp.Title, 
    tp.Score, 
    tp.ViewCount, 
    tp.Tags, 
    tp.CloseVotes, 
    tp.ReopenVotes, 
    b.Name AS BadgeName
FROM 
    top_users tu
JOIN 
    top_posts tp ON tu.Id = tp.Id
JOIN 
    badges b ON tu.Id = b.UserId
ORDER BY 
    tu.UpVotes DESC, 
    tp.Score DESC;