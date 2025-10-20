-- {"query": "2033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 417} 

WITH RecentActivityCTE AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate AS PostCreationDate, 
        COALESCE(p.LastEditDate, p.LastActivityDate) AS LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COALESCE(p.LastEditDate, p.LastActivityDate) DESC) AS ActivityRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
UserBadgesCTE AS (
    SELECT 
        ub.UserId, 
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Class) AS BadgeNames
    FROM 
        (SELECT 
            b.UserId, 
            b.Name, 
            b.Class, 
            RANK() OVER (PARTITION BY b.UserId ORDER BY b.Class) AS BadgeRank
        FROM 
            Badges b
        ) ub
    WHERE 
        ub.BadgeRank <= 3
    GROUP BY 
        ub.UserId
)
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    ra.PostId, 
    ra.Title AS RecentPostTitle, 
    u.Views + u.UpVotes AS ActivityScore, 
    COALESCE(ub.BadgeNames, 'No Badges') AS TopBadges
FROM 
    Users u
LEFT JOIN 
    RecentActivityCTE ra ON ra.ActivityRank = 1 AND ra.PostId IN (
        SELECT 
            PostId 
        FROM 
            Votes v 
        WHERE 
            v.VoteTypeId = 2 
        GROUP BY 
            v.PostId 
        HAVING 
            COUNT(v.Id) > 5
    )
LEFT JOIN 
    UserBadgesCTE ub ON u.Id = ub.UserId
WHERE 
    u.Reputation > 1000
ORDER BY 
    ActivityScore DESC, u.Reputation DESC;
