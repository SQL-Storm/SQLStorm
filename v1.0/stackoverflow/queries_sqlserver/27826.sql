
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
PostTags AS (
    SELECT 
        p.Id AS PostId,
        value AS Tag
    FROM 
        Posts p
    CROSS APPLY STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), '><') AS TagList(value)
    WHERE 
        p.PostTypeId = 1 
),
MostPopularTags AS (
    SELECT 
        Tag,
        COUNT(DISTINCT PostId) AS TagCount
    FROM 
        PostTags
    GROUP BY 
        Tag
    ORDER BY 
        TagCount DESC
    OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
)
SELECT 
    ur.DisplayName,
    ur.Reputation,
    ur.BadgeCount,
    rp.Title,
    rp.Body,
    rp.CreationDate,
    rp.Score,
    STRING_AGG(mt.Tag, ', ') AS PopularTags
FROM 
    RankedPosts rp
JOIN 
    UserReputation ur ON rp.OwnerUserId = ur.UserId
JOIN 
    PostTags pt ON rp.PostId = pt.PostId
JOIN 
    MostPopularTags mt ON pt.Tag = mt.Tag
WHERE 
    rp.PostRank = 1 
GROUP BY 
    ur.DisplayName, ur.Reputation, ur.BadgeCount, rp.Title, rp.Body, rp.CreationDate, rp.Score
ORDER BY 
    ur.Reputation DESC;
