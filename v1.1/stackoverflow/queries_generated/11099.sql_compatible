WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COUNT(v.Id) OVER (PARTITION BY p.Id) AS VoteCount,
        p.OwnerUserId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
UserActivity AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(Id) AS ActivityCount
    FROM 
        Posts
    WHERE 
        CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
    GROUP BY 
        OwnerUserId
),
TopUsers AS (
    SELECT 
        ua.UserId,
        ua.ActivityCount
    FROM 
        UserActivity ua
    WHERE 
        ua.ActivityCount > (SELECT AVG(ActivityCount) FROM UserActivity)
),
PostTags AS (
    SELECT 
        p.Id, 
        -- split tags like '<tag1><tag2>' into array of tags in standard SQL: use REPLACE/STRING functions where available.
        -- For portability, return as text with separators; some dialects support SPLIT or STRING_TO_ARRAY. Use a simple replacement to remove angle brackets and split by '><' where supported.
        REGEXP_REPLACE(p.Tags, '^<|>$', '', 'g') AS TagsPlain
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.PostType, 
    rp.VoteCount, 
    pt.TagsPlain AS Tags,
    COALESCE(tu.ActivityCount, 0) AS UserActivityCount,
    CASE 
        WHEN rp.Score > 10 AND rp.ViewCount > 100 THEN 'Highly Active'
        WHEN rp.Score > 5 AND rp.ViewCount > 50 THEN 'Moderately Active'
        ELSE 'Low Activity'
    END AS ActivityLevel
FROM 
    RecentPosts rp
LEFT JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.UserId
LEFT JOIN 
    PostTags pt ON rp.Id = pt.Id
ORDER BY 
    rp.CreationDate DESC, 
    rp.Score DESC, 
    rp.ViewCount DESC
LIMIT 10;