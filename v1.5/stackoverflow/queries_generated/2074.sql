-- {"query": "2074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 452} 

WITH RecentUpdates AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY ph.CreationDate DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    WHERE 
        ph.PostHistoryTypeId IN (4, 5, 6)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        COUNT(b.Id) AS TotalBadges,
        MIN(u.CreationDate) OVER () AS EarliestUserCreation
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
)
SELECT 
    u.DisplayName,
    ra.Title AS RecentTitle,
    ua.UpVotes,
    ua.DownVotes,
    ua.TotalBadges,
    (ua.UpVotes - ua.DownVotes) AS NetVotes,
    CASE 
        WHEN ua.UpVotes > 100 THEN 'Prolific Voter'
        WHEN ua.TotalBadges > 10 THEN 'Decorated User'
        ELSE 'Regular User'
    END AS UserCategory,
    ua.EarliestUserCreation
FROM 
    Users u
JOIN 
    UserActivity ua ON u.Id = ua.UserId
LEFT JOIN 
    RecentUpdates ra ON ra.rn = 1 AND ra.PostId IN (
        SELECT ra.PostId 
        FROM RecentUpdates ra_sub 
        WHERE ra_sub.PostId = ra.PostId AND ra_sub.rn = 1
    )
WHERE 
    u.LastAccessDate > ua.EarliestUserCreation + INTERVAL '1 year'
ORDER BY 
    NetVotes DESC, ua.TotalBadges DESC, UserCategory;
