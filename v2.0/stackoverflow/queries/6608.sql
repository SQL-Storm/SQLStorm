-- {"query": "6608.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 330}
SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoinDate,
    STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS RecentBadges,
    MAX(ph.RevisionGUID) AS LastRevisionGUID
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Id IN (
        SELECT 
            UserId 
        FROM 
            Votes 
        WHERE 
            VoteTypeId = 1 
            AND CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
    )
AND 
    p.Id IN (
        SELECT 
            pl.PostId 
        FROM 
            PostLinks pl 
        WHERE 
            pl.LinkTypeId = 1
    )
GROUP BY 
    u.DisplayName, u.Reputation, u.CreationDate
HAVING 
    AVG(p.Score) > 10
ORDER BY 
    TotalPosts DESC, 
    MaxReputation DESC;