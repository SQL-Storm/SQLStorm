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
badges_cte AS (
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
    tu.Id,
    tu.DisplayName, 
    tu.UpVotes, 
    tu.DownVotes, 
    tu.PostCount, 
    tp.Id AS PostId,
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
    badges_cte b ON tu.Id = b.UserId
GROUP BY
    tu.Id,
    tu.DisplayName,
    tu.UpVotes,
    tu.DownVotes,
    tu.PostCount,
    tp.Id,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    tp.CloseVotes,
    tp.ReopenVotes,
    b.Name
ORDER BY 
    tu.UpVotes DESC, 
    tp.Score DESC;