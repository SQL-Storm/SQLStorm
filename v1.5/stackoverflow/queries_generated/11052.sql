-- {"query": "11052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 696} 

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
        p.CreationDate > NOW() - INTERVAL '30 days' 
        AND p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId, 
        COUNT(Id) AS PostCount, 
        AVG(Score) AS AvgScore
    FROM 
        Posts
    WHERE 
        CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        UserId
    HAVING 
        COUNT(Id) > 10
),
PostTags AS (
    SELECT 
        p.Id, 
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'') AS Tags
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
TaggedPosts AS (
    SELECT 
        pt.Id, 
        t.TagName
    FROM 
        PostTags pt
    CROSS JOIN 
        unnest(pt.Tags) AS TagId
    JOIN 
        Tags t ON t.Id = TagId::int
),
BadgeEarners AS (
    SELECT 
        b.UserId, 
        COUNT(b.Id) AS BadgeCount
    FROM 
        Badges b
    GROUP BY 
        b.UserId
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
    ARRAY_AGG(tp.TagName) AS Tags,
    tu.PostCount, 
    tu.AvgScore, 
    be.BadgeCount
FROM 
    RecentPosts rp
JOIN 
    TaggedPosts tp ON rp.Id = tp.Id
LEFT JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.UserId
LEFT JOIN 
    BadgeEarners be ON rp.OwnerUserId = be.UserId
GROUP BY 
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.Reputation, rp.TotalBounty, tu.PostCount, tu.AvgScore, be.BadgeCount
ORDER BY 
    rp.Score DESC, rp.ViewCount DESC, rp.TotalBounty DESC
LIMIT 10;
