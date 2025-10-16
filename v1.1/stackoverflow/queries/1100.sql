WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
        AND p.Score IS NOT NULL
),
UserInteractions AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(c.Id) AS CommentCount,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id,
        u.DisplayName
),
TopPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        COALESCE(pc.TotalComments, 0) AS TotalComments,
        COALESCE(owner_up.UpVotes, 0) AS TotalUpVotes,
        COALESCE(owner_up.DownVotes, 0) AS TotalDownVotes
    FROM 
        RankedPosts rp
    LEFT JOIN LATERAL (
        SELECT p.OwnerUserId
        FROM Posts p
        WHERE p.Id = rp.PostId
        LIMIT 1
    ) AS post_owner ON TRUE
    LEFT JOIN UserInteractions owner_up ON post_owner.OwnerUserId = owner_up.UserId
    LEFT JOIN (
        SELECT c.PostId, COUNT(*) AS TotalComments
        FROM Comments c
        GROUP BY c.PostId
    ) pc ON rp.PostId = pc.PostId
    WHERE 
        rp.Rank <= 5
)
SELECT
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.TotalComments,
    tp.TotalUpVotes,
    tp.TotalDownVotes,
    CASE 
        WHEN tp.TotalUpVotes = 0 THEN 'No Upvotes'
        WHEN tp.TotalDownVotes = 0 THEN 'No Downvotes'
        ELSE 'Balanced Votes'
    END AS VoteStatus
FROM 
    TopPosts tp
ORDER BY 
    tp.Score DESC, tp.ViewCount DESC;