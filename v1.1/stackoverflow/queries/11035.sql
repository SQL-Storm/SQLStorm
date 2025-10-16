WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
        p.OwnerUserId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE 
        p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
        AND p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation, p.OwnerUserId
),
TopUsers AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore
    FROM 
        Posts
    WHERE 
        PostTypeId = 1
        AND CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 10
),
PostTags AS (
    SELECT 
        p.Id, 
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
    tu.UserId, 
    tu.PostCount, 
    tu.AvgScore
FROM 
    RecentPosts rp
JOIN 
    PostTags pt ON rp.Id = pt.Id
LEFT JOIN 
    PostComments pc ON rp.Id = pc.PostId
LEFT JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.UserId
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.Reputation, rp.TotalBounty, rp.OwnerUserId, tu.UserId, tu.PostCount, tu.AvgScore, pc.CommentCount
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.TotalBounty DESC
FETCH FIRST 10 ROWS ONLY;