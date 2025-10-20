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
        p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY
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
        CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' YEAR
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 10
),
PostTags AS (
    SELECT 
        p.Id, 
        CASE
          WHEN p.Tags IS NULL THEN NULL
          WHEN CHAR_LENGTH(p.Tags) >= 2 THEN
            -- remove leading '<' and trailing '>' then split on '><'
            regexp_split_to_array(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><')
          ELSE ARRAY[]::text[]
        END AS Tags
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
TaggedPosts AS (
    SELECT 
        pt.Id, 
        t.tag_text AS TagName,
        CAST(t.tag_text AS INTEGER) AS TagIdInt
    FROM 
        PostTags pt
    CROSS JOIN LATERAL (
      SELECT unnest(pt.Tags) AS tag_text
    ) t
    JOIN 
        Tags tg ON tg.Id = CAST(t.tag_text AS INTEGER)
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
    rp.Id, rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerDisplayName, rp.Reputation, rp.TotalBounty, rp.OwnerUserId, tu.PostCount, tu.AvgScore, be.BadgeCount
ORDER BY 
    rp.Score DESC, rp.ViewCount DESC, rp.TotalBounty DESC
LIMIT 10;