WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE 
        p.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
        AND p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        p.OwnerUserId AS UserId, 
        COUNT(p.Id) AS PostCount, 
        AVG(p.Score) AS AvgScore
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    GROUP BY 
        p.OwnerUserId
    HAVING 
        COUNT(p.Id) > 10
),
PostTags AS (
    SELECT 
        p.Id AS PostId, 
        t.TagName
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.Id IN (SELECT Id FROM RecentPosts)
),
PostComments AS (
    SELECT 
        c.PostId, 
        COUNT(c.Id) AS CommentCount
    FROM 
        Comments c
    GROUP BY 
        c.PostId
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.TotalBounty, 
    STRING_AGG(pt.TagName, ', ') AS Tags, 
    COALESCE(pc.CommentCount, 0) AS CommentCount,
    COALESCE(tu.UserId, 0) AS UserId, 
    COALESCE(tu.PostCount, 0) AS PostCount, 
    COALESCE(tu.AvgScore, 0) AS AvgScore
FROM 
    RecentPosts rp
JOIN 
    PostTags pt ON rp.Id = pt.PostId
LEFT JOIN 
    PostComments pc ON rp.Id = pc.PostId
LEFT JOIN 
    TopUsers tu ON rp.OwnerDisplayName = (SELECT u.DisplayName FROM Users u WHERE u.Id = tu.UserId)
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.Reputation, rp.TotalBounty, pc.CommentCount, tu.UserId, tu.PostCount, tu.AvgScore
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.TotalBounty DESC
LIMIT 10;