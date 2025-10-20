WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        u.DisplayName AS OwnerDisplayName,
        p.ViewCount,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    GROUP BY 
        p.Id, p.Title, u.DisplayName, p.ViewCount, p.CreationDate, p.OwnerUserId
),
TopUsers AS (
    SELECT 
        OwnerDisplayName,
        COUNT(PostId) AS TotalPosts,
        SUM(ViewCount) AS TotalViews,
        SUM(UpVoteCount) AS TotalUpVotes,
        SUM(DownVoteCount) AS TotalDownVotes
    FROM 
        RankedPosts
    WHERE 
        PostRank = 1
    GROUP BY 
        OwnerDisplayName
    ORDER BY 
        TotalPosts DESC
    LIMIT 10
)
SELECT 
    tu.OwnerDisplayName,
    tu.TotalPosts,
    tu.TotalViews,
    tu.TotalUpVotes,
    tu.TotalDownVotes,
    AVG(rp.ViewCount) AS AverageViewsPerPost,
    AVG(rp.CommentCount) AS AverageCommentsPerPost
FROM 
    TopUsers tu
JOIN 
    RankedPosts rp ON tu.OwnerDisplayName = rp.OwnerDisplayName
GROUP BY 
    tu.OwnerDisplayName, tu.TotalPosts, tu.TotalViews, tu.TotalUpVotes, tu.TotalDownVotes
ORDER BY 
    tu.TotalPosts DESC;