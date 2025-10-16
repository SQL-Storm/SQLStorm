-- {"query": "2030.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 404} 

WITH RecencyCTE AS (
    SELECT 
        UserId, 
        PostId, 
        RANK() OVER(PARTITION BY UserId ORDER BY CreationDate DESC) AS Rank
    FROM 
        Posts
    WHERE 
        PostTypeId = 1
),
UserBadgeCounts AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    p.Title AS RecentPostTitle,
    p.CreationDate AS RecentPostDate,
    COALESCE(vt.Name, 'No Vote Type') AS VoteTypeName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges 
FROM 
    Users u
LEFT JOIN 
    RecencyCTE r ON u.Id = r.UserId AND r.Rank = 1
LEFT JOIN 
    Posts p ON r.PostId = p.Id
LEFT JOIN 
    (SELECT v.UserId, MAX(v.VoteTypeId) AS MaxVoteTypeId 
     FROM Votes v 
     GROUP BY v.UserId) uv ON u.Id = uv.UserId
LEFT JOIN 
    VoteTypes vt ON uv.MaxVoteTypeId = vt.Id
LEFT JOIN 
    UserBadgeCounts ubc ON u.Id = ubc.UserId
WHERE 
    u.Reputation > 1000 
    AND (ubc.GoldBadges > 2 OR p.CreationDate > '2022-01-01')
ORDER BY 
    u.UpVotes DESC, 
    p.CreationDate DESC;
