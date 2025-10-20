-- {"query": "32067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 509} 
WITH RecentPopularPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
TopUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Users u 
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
    HAVING 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 100
),
BadgeDistribution AS (
    SELECT 
        Name, 
        Count(Id) AS BadgeCount
    FROM 
        Badges
    GROUP BY 
        Name
    HAVING 
        COUNT(Id) > 50
),
LinkedPosts AS (
    SELECT 
        pl.CreationDate AS LinkCreationDate, 
        p.Title AS RelatedPostTitle, 
        pl.PostId, 
        pl.RelatedPostId
    FROM 
        PostLinks pl
    JOIN 
        Posts p ON pl.RelatedPostId = p.Id
    WHERE 
        pl.LinkTypeId = 1
)
SELECT 
    rp.Id AS PostId, 
    rp.Title AS PostTitle, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    tu.DisplayName AS TopUser, 
    tu.Reputation, 
    tu.UpVoteCount AS TotalUpVotes, 
    bd.BadgeCount, 
    lp.LinkCreationDate, 
    lp.RelatedPostTitle
FROM 
    RecentPopularPosts rp
JOIN 
    TopUsers tu ON tu.Id = rp.Id
LEFT JOIN 
    BadgeDistribution bd ON bd.Name LIKE CONCAT('%',rp.Title,'%')
LEFT JOIN 
    LinkedPosts lp ON lp.PostId = rp.Id
WHERE 
    rp.rn <= 100
ORDER BY 
    rp.Score DESC, tu.Reputation DESC;