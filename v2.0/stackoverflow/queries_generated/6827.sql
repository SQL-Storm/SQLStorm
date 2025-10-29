-- {"query": "6827.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 346} 

SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoined,
    STRING_AGG(DISTINCT b.Name, ', ') WITHIN GROUP (ORDER BY b.Date DESC) AS BadgesEarned,
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
            VoteTypeId = 1 AND 
            CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
    )
AND 
    p.Id IN (
        SELECT 
            PostId 
        FROM 
            PostHistory 
        WHERE 
            PostHistoryTypeId IN (1, 2) 
        GROUP BY 
            PostId 
        HAVING 
            COUNT(DISTINCT PostHistoryTypeId) > 1
    )
GROUP BY 
    u.Id
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    TotalPosts DESC;
