WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN vv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN vv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes vv ON p.Id = vv.PostId AND vv.VoteTypeId IN (2, 3)
    GROUP BY 
        u.Id
),
UserBadges AS (
    SELECT 
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM 
        Badges b
    WHERE 
        b.Class IN (1, 2)
    GROUP BY 
        b.UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(au.PostCount, 0) AS PostCount,
    au.Upvotes,
    au.Downvotes,
    ub.BadgeNames,
    (au.Upvotes - au.Downvotes) AS NetVotes,
    AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY u.Id) AS AvgPostScore
FROM 
    Users u
LEFT JOIN 
    ActiveUsers au ON u.Id = au.UserId
LEFT JOIN 
    UserBadges ub ON u.Id = ub.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
WHERE 
    u.Reputation > 1000 
    AND (au.Upvotes > 10 OR au.Downvotes < 5)
ORDER BY 
    NetVotes DESC NULLS LAST, u.DisplayName;