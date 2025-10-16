-- {"query": "2097.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 379} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
    FROM 
        Users u
    WHERE 
        u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TopVotedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS dr
    FROM 
        Posts p
    WHERE 
        p.Score > 0
),
TopBadgedUsers AS (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgeCount,
        MIN(b.Date) AS FirstBadgeDate
    FROM 
        Badges b
    WHERE 
        b.Class = 1
    GROUP BY 
        b.UserId
    HAVING 
        COUNT(*) >= 3
)
SELECT 
    u.DisplayName,
    COALESCE(p.Title, 'No Posts') AS TopPostTitle,
    b.BadgeCount,
    v.UserId AS VoterUserId,
    CASE
        WHEN u.Id = v.UserId THEN 'Voter is Active User' 
        ELSE 'Voter is Different User'
    END AS VoterStatus
FROM 
    RecentActiveUsers u
LEFT JOIN 
    TopVotedPosts p ON u.Id = p.Id AND p.dr = 1
LEFT JOIN 
    TopBadgedUsers b ON u.Id = b.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
WHERE 
    u.rn <= 10 AND (u.DisplayName LIKE 'A%' OR b.BadgeCount > 5)
ORDER BY 
    u.rn, b.FirstBadgeDate;