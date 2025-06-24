WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title, 
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(v.VoteTypeId IN (2)), 0) AS UpVotes,
        COALESCE(SUM(v.VoteTypeId IN (3)), 0) AS DownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
PostDetails AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedCount,
        MAX(ph.CreationDate) AS LastEditedDate
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
        p.Id
)
SELECT 
    us.DisplayName,
    us.UpVotes,
    us.DownVotes,
    ps.Title AS RecentPostTitle,
    ps.CreationDate,
    pd.CommentCount,
    pd.ClosedCount,
    pd.LastEditedDate
FROM 
    UserStats us
LEFT JOIN 
    RankedPosts ps ON us.UserId = ps.OwnerUserId AND ps.PostRank = 1
LEFT JOIN 
    PostDetails pd ON ps.Id = pd.PostId
WHERE 
    us.UpVotes > 10 
    OR (us.BadgeCount > 5 AND pd.ClosedCount = 0)
ORDER BY 
    us.UpVotes DESC, 
    us.DownVotes ASC
FETCH FIRST 10 ROWS ONLY;
