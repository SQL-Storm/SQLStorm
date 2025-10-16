WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        p.CommentCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation, 
        t.TagName,
        p.OwnerUserId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    JOIN 
        Tags t ON p.Id = t.Id
    WHERE 
        p.CreationDate > (DATE '2024-10-01' - INTERVAL '30' DAY)
),
UserActivity AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(*) AS ActivityCount
    FROM 
        Posts
    WHERE 
        CreationDate > (DATE '2024-10-01' - INTERVAL '30' DAY)
    GROUP BY 
        OwnerUserId
),
BadgeEarners AS (
    SELECT 
        UserId, 
        COUNT(*) AS BadgeCount
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.AnswerCount, 
    rp.CommentCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.TagName, 
    ua.ActivityCount, 
    be.BadgeCount
FROM 
    RecentPosts rp
LEFT JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN 
    BadgeEarners be ON rp.OwnerUserId = be.UserId
WHERE 
    (rp.Score > 10 OR rp.ViewCount > 1000) 
    AND ((ua.ActivityCount > 5) OR (be.BadgeCount > 3))
ORDER BY 
    rp.CreationDate DESC, 
    rp.Score DESC, 
    rp.ViewCount DESC;