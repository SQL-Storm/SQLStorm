WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR
), CommentsWithPostInfo AS (
    SELECT 
        c.Id AS CommentId,
        c.Score AS CommentScore,
        c.Text,
        c.CreationDate AS CommentCreationDate,
        c.PostId,
        p.Title AS PostTitle,
        p.CreationDate AS PostCreationDate
    FROM 
        Comments c
    JOIN 
        Posts p ON c.PostId = p.Id
    WHERE 
        c.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH
), UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM 
        Badges b
    GROUP BY 
        b.UserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    COALESCE(rb.TotalBadges, 0) AS BadgeCount,
    COALESCE(rb.BadgeNames, 'No Badges') AS Badges,
    rp.PostId,
    rp.Title,
    rp.Score AS PostScore,
    rp.ViewCount,
    COALESCE(c.CommentId, -1) AS LatestCommentId,
    COALESCE(c.CommentScore, 0) AS LatestCommentScore,
    COALESCE(c.Text, 'No Comments') AS LatestCommentText,
    CASE WHEN c.CommentCreationDate IS NULL THEN NULL ELSE c.CommentCreationDate END AS LatestCommentDate
FROM 
    Users u
LEFT JOIN 
    UserBadges rb ON u.Id = rb.UserId
LEFT JOIN 
    RankedPosts rp ON u.Id = rp.OwnerUserId AND rp.UserPostRank = 1
LEFT JOIN 
    CommentsWithPostInfo c ON rp.PostId = c.PostId
WHERE 
    u.Reputation > 1000
ORDER BY 
    u.Reputation DESC, 
    rp.Score DESC;