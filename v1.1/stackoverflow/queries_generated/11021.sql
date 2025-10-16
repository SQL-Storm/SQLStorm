-- {"query": "11021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 519} 

WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        CASE 
            WHEN COUNT(v.Id) OVER (PARTITION BY p.Id) > 0 THEN SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) 
            ELSE 0 
        END AS UpVotes,
        CASE 
            WHEN COUNT(v.Id) OVER (PARTITION BY p.Id) > 0 THEN SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) 
            ELSE 0 
        END AS DownVotes
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
UserActivity AS (
    SELECT 
        UserId, 
        COUNT(Id) AS TotalPosts, 
        SUM(Score) AS TotalScore, 
        SUM(ViewCount) AS TotalViews
    FROM 
        Posts
    GROUP BY 
        UserId
),
TopUsers AS (
    SELECT 
        UserId, 
        TotalPosts, 
        TotalScore, 
        TotalViews
    FROM 
        UserActivity
    WHERE 
        TotalPosts > 10
    ORDER BY 
        TotalScore DESC
    LIMIT 10
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.UpVotes, 
    rp.DownVotes,
    ua.TotalPosts, 
    ua.TotalScore, 
    ua.TotalViews
FROM 
    RecentPosts rp
JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.UserId
JOIN 
    UserActivity ua ON tu.UserId = ua.UserId
WHERE 
    rp.UpVotes > rp.DownVotes
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC
LIMIT 20;
