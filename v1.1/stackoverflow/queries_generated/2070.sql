-- {"query": "2070.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 497} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        COUNT(c.Id) OVER (PARTITION BY p.OwnerUserId) AS CommentCount,
        SUM(v.BountyAmount) OVER (PARTITION BY v.UserId) AS TotalBountyReceived,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS RecentPostOrder
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE 
        p.CreationDate > u.CreationDate + INTERVAL '1 year'
),
ActiveUsers AS (
    SELECT 
        UserId,
        DisplayName,
        COUNT(PostId) AS TotalPosts,
        COALESCE(MAX(CommentCount), 0) AS MaxComments,
        COALESCE(TotalBountyReceived, 0) AS TotalBounty
    FROM 
        UserActivity
    WHERE 
        PostId IS NOT NULL
    GROUP BY 
        UserId, DisplayName, TotalBountyReceived
    HAVING 
        COUNT(PostId) > 10
)
SELECT 
    u.DisplayName,
    COALESCE(p.Score, 0) AS PostScore,
    ltp.Name AS LinkType,
    COALESCE(ph.Name, 'No History') AS PostHistory,
    a.MaxComments,
    a.TotalBounty
FROM 
    ActiveUsers a
INNER JOIN 
    Users u ON a.UserId = u.Id
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    LinkTypes ltp ON pl.LinkTypeId = ltp.Id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
WHERE 
    a.TotalBounty > 100
AND 
    COALESCE(p.Score, 0) > 0
ORDER BY 
    a.MaxComments DESC, a.TotalBounty DESC
LIMIT 50;
