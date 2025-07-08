
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.ViewCount DESC) AS TagRank,
        p.OwnerUserId
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND 
        p.CreationDate > DATEADD(year, -1, '2024-10-01 12:34:56') AND 
        p.ViewCount > 1000
),
TagStatistics AS (
    SELECT 
        value AS Tag,
        COUNT(*) AS PostCount,
        AVG(DATEDIFF(second, CreationDate, '2024-10-01 12:34:56')) AS AvgAgeInSeconds
    FROM 
        RankedPosts,
        FLATTEN(input => SPLIT(Tags, '>')) AS t
    GROUP BY 
        value
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(v.BountyAmount) AS TotalBounty,
        COUNT(DISTINCT p.Id) AS PostsCount
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8  
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    rs.PostId,
    rs.Title,
    rs.Body,
    ts.Tag,
    ts.PostCount,
    ts.AvgAgeInSeconds,
    ur.DisplayName AS UserName,
    ur.TotalBounty,
    ur.PostsCount
FROM 
    RankedPosts rs
JOIN 
    TagStatistics ts ON ts.Tag IN (SELECT value FROM FLATTEN(input => SPLIT(rs.Tags, '>')))
JOIN 
    UserReputation ur ON ur.UserId = rs.OwnerUserId
WHERE 
    rs.TagRank = 1
ORDER BY 
    ts.PostCount DESC, 
    ur.TotalBounty DESC
LIMIT 10;
