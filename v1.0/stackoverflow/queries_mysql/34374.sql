
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        @row_number := IF(@current_partition = pt.Name, @row_number + 1, 1) AS Rank,
        @current_partition := pt.Name,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    CROSS JOIN (SELECT @row_number := 0, @current_partition := '') AS vars
    WHERE 
        p.CreationDate > DATE_SUB(CURDATE(), INTERVAL 1 YEAR)
    GROUP BY 
        p.Id, pt.Name, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId
),
TopPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        rp.CommentCount
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank <= 5
),
UserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
),
PostHistoryDetails AS (
    SELECT 
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        p.Title AS PostTitle,
        ph.Comment
    FROM 
        PostHistory ph
    JOIN 
        Posts p ON ph.PostId = p.Id
    WHERE 
        ph.PostHistoryTypeId IN (10, 11)  
)
SELECT 
    tp.Title AS TopPostTitle,
    tp.CreationDate AS PostCreationDate,
    tp.Score AS PostScore,
    tb.DisplayName AS UserDisplayName,
    ub.BadgeCount AS UserBadgeCount,
    COALESCE(phd.Comment, 'No comments') AS PostHistoryComment
FROM 
    TopPosts tp
JOIN 
    Users tb ON tp.OwnerUserId = tb.Id
LEFT JOIN 
    UserBadges ub ON tb.Id = ub.UserId
LEFT JOIN 
    PostHistoryDetails phd ON tp.PostId = phd.PostId
WHERE 
    ub.BadgeCount > 1  
ORDER BY 
    tp.Score DESC, tp.CreationDate DESC;
