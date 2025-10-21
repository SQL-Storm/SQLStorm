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
        p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
),
UserActivity AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(Id) AS ActivityCount
    FROM 
        Posts
    WHERE 
        CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
    GROUP BY 
        OwnerUserId
),
TopUsers AS (
    SELECT 
        *
    FROM 
        UserActivity
    WHERE 
        ActivityCount > (SELECT AVG(ActivityCount) FROM UserActivity)
),
PostTags AS (
    SELECT 
        p.Id, 
        string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><') AS Tags
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
    pt.Tags,
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
GROUP BY
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.PostType,
    rp.VoteCount,
    pt.Tags,
    tu.ActivityCount
ORDER BY 
    rp.CreationDate DESC, 
    rp.Score DESC, 
    rp.ViewCount DESC
LIMIT 10;