WITH RECURSIVE PopularPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.OwnerUserId,
        1 AS Level
    FROM 
        Posts p
    WHERE 
        p.Score > 10
    UNION ALL
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.OwnerUserId,
        pp.Level + 1
    FROM 
        Posts p
    JOIN 
        PopularPosts pp ON p.ParentId = pp.Id
    WHERE 
        p.Score > 10
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
PostActivity AS (
    SELECT 
        p.Id AS PostId,
        COALESCE(c.CommentCount, 0) AS CommentCount,
        COALESCE(v.VoteCount, 0) AS VoteCount
    FROM 
        Posts p
    LEFT JOIN 
        (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) c ON p.Id = c.PostId
    LEFT JOIN 
        (SELECT PostId, COUNT(*) AS VoteCount FROM Votes GROUP BY PostId) v ON p.Id = v.PostId
)
SELECT 
    pp.Title AS PopularPostTitle,
    pp.Score AS PopularPostScore,
    ur.UserId,
    ur.Reputation AS UserReputation,
    ur.PostCount AS UserPostCount,
    pa.CommentCount,
    pa.VoteCount
FROM 
    PopularPosts pp
JOIN 
    UserReputation ur ON pp.OwnerUserId = ur.UserId
JOIN 
    PostActivity pa ON pp.Id = pa.PostId
WHERE 
    ur.Reputation > 5000
ORDER BY 
    pp.Score DESC, 
    ur.Reputation DESC 
LIMIT 10;

-- Including Badges and Post History details for additional complexity
WITH BadgeCount AS (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgeCount
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
PostHistoryDetails AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        MAX(ph.CreationDate) OVER (PARTITION BY ph.PostId) AS LastEditDate,
        ph.Comment
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (4, 5, 10, 12) -- Edits and Closure types
)
SELECT 
    pp.Title,
    b.BadgeCount,
    phd.LastEditDate
FROM 
    PopularPosts pp
LEFT JOIN 
    BadgeCount b ON pp.OwnerUserId = b.UserId
LEFT JOIN 
    PostHistoryDetails phd ON pp.Id = phd.PostId
WHERE 
    phd.LastEditDate IS NOT NULL
ORDER BY 
    b.BadgeCount DESC, 
    pp.Score DESC 
LIMIT 5;
