-- Performance benchmarking query
WITH PostSummary AS (
    SELECT 
        p.Id AS PostId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(v.VoteTypeId = 2), 0) AS UpVotes, -- VoteTypeId 2 for UpMod
        COALESCE(SUM(v.VoteTypeId = 3), 0) AS DownVotes -- VoteTypeId 3 for DownMod
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id, p.CreationDate, p.Score, p.ViewCount
),
UserSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        AVG(u.Reputation) AS AverageReputation,
        SUM(p.ViewCount) AS TotalViews
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    ps.PostId,
    ps.CreationDate,
    ps.Score,
    ps.ViewCount,
    ps.CommentCount,
    ps.UpVotes,
    ps.DownVotes,
    us.UserId,
    us.DisplayName,
    us.BadgeCount,
    us.AverageReputation,
    us.TotalViews
FROM 
    PostSummary ps
JOIN 
    Users us ON ps.PostId = us.Id
ORDER BY 
    ps.Score DESC, ps.ViewCount DESC;
