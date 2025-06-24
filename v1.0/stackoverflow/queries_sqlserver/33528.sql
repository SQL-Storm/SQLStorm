
WITH UserBadges AS (
    SELECT 
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        b.Date,
        1 AS Level
    FROM 
        Badges b
    WHERE 
        b.Class = 1  
    UNION ALL
    SELECT 
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        b.Date,
        ub.Level + 1
    FROM 
        Badges b
    INNER JOIN 
        UserBadges ub ON b.UserId = ub.UserId
    WHERE 
        b.Class IN (2, 3) AND ub.Level < 5  
),
PostTagCTE AS (
    SELECT 
        p.Id AS PostId,
        COUNT(DISTINCT t.TagName) AS TagCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        STRING_AGG(t.TagName, ', ') AS Tags
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    CROSS APPLY 
        (SELECT value AS TagName FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '><')) AS t
    GROUP BY 
        p.Id
),
RecentPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        COALESCE(u.DisplayName, 'Community User') AS OwnerDisplayName
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > DATEADD(DAY, -30, GETDATE())
),
BenchmarkingStats AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.OwnerDisplayName,
        pt.TagCount,
        pt.UpVoteCount,
        pt.DownVoteCount,
        ub.BadgeName,
        ub.Level AS BadgeLevel
    FROM 
        RecentPosts rp
    LEFT JOIN 
        PostTagCTE pt ON rp.PostId = pt.PostId
    LEFT JOIN 
        UserBadges ub ON rp.OwnerDisplayName = CAST(ub.UserId AS VARCHAR)
    ORDER BY 
        rp.CreationDate DESC
)
SELECT 
    PostId,
    Title,
    CreationDate,
    OwnerDisplayName,
    TagCount,
    UpVoteCount,
    DownVoteCount,
    COALESCE(BadgeName + ' (Level ' + CAST(BadgeLevel AS VARCHAR) + ')', 'No Badges') AS BadgeDetails
FROM 
    BenchmarkingStats
WHERE 
    TagCount > 3 AND UpVoteCount > DownVoteCount  
ORDER BY 
    CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
