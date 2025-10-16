WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(v.BountyAmount) AS TotalBounty,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        u.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years'
    GROUP BY 
        u.Id, u.DisplayName
),
RecentCommentsPerPost AS (
    SELECT 
        PostId, COUNT(*) AS CommentCount 
    FROM 
        Comments 
    WHERE 
        CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months' 
    GROUP BY 
        PostId
),
TopPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.CreationDate,
        rp.OwnerUserId,
        rp.ViewCount,
        rp.ScoreRank,
        rp.CommentCount AS CommentCountAllTime,
        ua.UserId,
        ua.DisplayName,
        ua.TotalUpvotes,
        rp.CommentCount AS RankedCommentCount,
        rc.CommentCount AS RecentCommentCount
    FROM 
        RankedPosts rp
    JOIN 
        UserActivity ua ON rp.OwnerUserId = ua.UserId
    LEFT JOIN 
        RecentCommentsPerPost rc ON rp.PostId = rc.PostId
    WHERE 
        rp.ScoreRank <= 5
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.CreationDate,
    tp.OwnerUserId,
    tp.ViewCount,
    tp.ScoreRank,
    tp.CommentCountAllTime,
    tp.RecentCommentCount,
    tp.UserId,
    tp.DisplayName,
    tp.TotalUpvotes,
    COALESCE(vd.TotalDownvotes, 0) AS TotalDownvotes,
    at.AssociatedTags,
    CASE 
        WHEN tp.Score IS NULL THEN 'No Score'
        ELSE 'Available Score'
    END AS ScoreStatus
FROM 
    TopPosts tp
LEFT JOIN (
    SELECT v.PostId, COUNT(*) AS TotalDownvotes
    FROM Votes v
    WHERE v.VoteTypeId = 3
    GROUP BY v.PostId
) vd ON vd.PostId = tp.PostId
LEFT JOIN (
    SELECT p.Id AS PostId, STRING_AGG(t.TagName, ', ') AS AssociatedTags
    FROM Posts p
    JOIN Tags t ON t.ExcerptPostId = p.Id
    GROUP BY p.Id
) at ON at.PostId = tp.PostId
ORDER BY 
    tp.Score DESC NULLS LAST, tp.TotalUpvotes DESC;