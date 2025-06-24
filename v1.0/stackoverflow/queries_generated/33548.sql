WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 -- Only questions
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        CreationDate,
        Score,
        ViewCount,
        OwnerDisplayName
    FROM 
        RankedPosts
    WHERE 
        PostRank = 1 -- Select the latest post of each user
),
PostStats AS (
    SELECT 
        pp.PostId,
        pp.Title,
        pp.CreationDate,
        pp.Score,
        pp.ViewCount,
        pp.OwnerDisplayName,
        COALESCE(c.CommentCount, 0) AS CommentCount,
        COALESCE(v.VoteCount, 0) AS Upvotes,
        COALESCE(b.BadgeCount, 0) AS BadgeCount
    FROM 
        TopPosts pp
    LEFT JOIN (
        SELECT 
            PostId, 
            COUNT(*) AS CommentCount 
        FROM 
            Comments 
        GROUP BY 
            PostId
    ) c ON pp.PostId = c.PostId
    LEFT JOIN (
        SELECT 
            PostId, 
            COUNT(*) AS VoteCount 
        FROM 
            Votes 
        WHERE 
            VoteTypeId = 2 -- Upvote
        GROUP BY 
            PostId
    ) v ON pp.PostId = v.PostId
    LEFT JOIN (
        SELECT 
            UserId,
            COUNT(*) AS BadgeCount
        FROM 
            Badges 
        GROUP BY 
            UserId
    ) b ON pp.OwnerDisplayName = (SELECT DisplayName FROM Users WHERE Id = b.UserId)
)
SELECT 
    ps.PostId,
    ps.Title,
    ps.CreationDate,
    ps.Score,
    ps.ViewCount,
    ps.OwnerDisplayName,
    ps.CommentCount,
    ps.Upvotes,
    ps.BadgeCount,
    CASE 
        WHEN ps.BadgeCount > 5 THEN 'Experienced'
        WHEN ps.BadgeCount BETWEEN 1 AND 5 THEN 'Novice'
        ELSE 'No Badges'
    END AS UserLevel
FROM 
    PostStats ps
WHERE 
    ps.Upvotes > 10
ORDER BY 
    ps.Score DESC, 
    ps.ViewCount DESC 
LIMIT 10;

-- Below is an example of using a CTE to generate a separate result set by user
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId 
        LEFT JOIN 
        Badges b ON u.Id = b.UserId 
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    up.DisplayName,
    up.TotalPosts,
    up.TotalBadges,
    CASE 
        WHEN up.TotalBadges > 10 THEN 'Elite'
        WHEN up.TotalBadges BETWEEN 6 AND 10 THEN 'Proficient'
        ELSE 'Beginner'
    END AS BadgeLevel
FROM 
    UserPostStats up
WHERE 
    up.TotalPosts > 5
ORDER BY 
    up.TotalBadges DESC;
