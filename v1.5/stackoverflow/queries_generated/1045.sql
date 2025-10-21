-- {"query": "1045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 448} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM 
        Posts p
    WHERE
        p.CreationDate >= NOW() - INTERVAL '1 year' AND
        p.Score > 0
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.Reputation
),
TopTags AS (
    SELECT 
        unnest(string_to_array(t.TagName, ',')) AS Tag,
        COUNT(pt.PostId) AS PostCount
    FROM 
        Tags t
    JOIN 
        Posts pt ON pt.Tags LIKE '%' || t.TagName || '%'
    GROUP BY 
        t.TagName
    HAVING 
        COUNT(pt.PostId) > 10
),
UserBadges AS (
    SELECT 
        b.UserId,
        ARRAY_AGG(b.Name ORDER BY b.Date DESC) AS BadgeList
    FROM 
        Badges b
    GROUP BY 
        b.UserId
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    ur.Reputation,
    ur.PostCount,
    COALESCE(tb.Tag, 'No Tags') AS TopTag,
    ub.BadgeList
FROM 
    RankedPosts rp
JOIN 
    UserReputation ur ON rp.OwnerUserId = ur.UserId
LEFT JOIN 
    TopTags tb ON tb.PostCount = (SELECT MAX(PostCount) FROM TopTags)
LEFT JOIN 
    UserBadges ub ON ub.UserId = rp.OwnerUserId
WHERE 
    rp.rn = 1
ORDER BY 
    rp.Score DESC, ur.Reputation DESC
LIMIT 50;
