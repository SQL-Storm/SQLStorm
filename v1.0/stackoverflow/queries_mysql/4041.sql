
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL 1 YEAR
        AND p.PostTypeId = 1
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(SUM(b.Class), 0) AS TotalBadgePoints,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM 
        Users u 
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id
),
TopContributors AS (
    SELECT 
        ur.UserId,
        ur.TotalBadgePoints,
        ur.Upvotes - ur.Downvotes AS NetVotes
    FROM 
        UserReputation ur
    WHERE 
        ur.TotalBadgePoints > 5
)
SELECT 
    p.Title,
    p.CreationDate,
    p.Score,
    u.DisplayName,
    COALESCE(tc.TotalBadgePoints, 0) AS BadgePoints,
    COALESCE(tc.NetVotes, 0) AS NetVotes,
    COUNT(c.Id) AS CommentCount
FROM 
    RankedPosts p
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    TopContributors tc ON u.Id = tc.UserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE 
    p.Rank = 1
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName, tc.TotalBadgePoints, tc.NetVotes
ORDER BY 
    p.Score DESC, p.CreationDate DESC
LIMIT 10;
