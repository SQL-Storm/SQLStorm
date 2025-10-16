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
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation, p.OwnerUserId
),
TopUsers AS (
    SELECT 
        OwnerUserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore, 
        SUM(ViewCount) AS TotalViews
    FROM 
        Posts
    WHERE 
        CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 5
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
        p.PostTypeId = 1
),
PostActivity AS (
    SELECT 
        p.Id, 
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    GROUP BY 
        p.Id
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
    pt.TagName,
    pa.EditCount,
    pa.CommentCount,
    tu.PostCount,
    tu.AvgScore,
    tu.TotalViews
FROM 
    RecentPosts rp
JOIN 
    PostTags pt ON rp.Id = pt.Id
JOIN 
    PostActivity pa ON rp.Id = pa.Id
JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.OwnerUserId
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.TotalBounty DESC
LIMIT 10;