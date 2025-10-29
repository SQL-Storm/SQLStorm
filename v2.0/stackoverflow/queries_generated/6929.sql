-- {"query": "6929.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 346} 

SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoined,
    STRING_AGG(DISTINCT p.Tags, ', ') WITHIN GROUP AS (ORDER BY p.Tags) AS PopularTags,
    AVG(ph.Score) AS AvgCommentScore
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Id IN (
        SELECT 
            ub.UserId 
        FROM 
            Badges ub
        WHERE 
            ub.Class = 1 AND ub.Date >= '2022-01-01'
    )
AND 
    p.LastActivityDate > p.CreationDate
AND 
    EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE 
            v.PostId = p.Id 
            AND v.VoteTypeId = 1
    )
GROUP BY 
    u.DisplayName
HAVING 
    AVG(ph.Score) > 0
ORDER BY 
    TotalPosts DESC, 
    MaxReputation DESC;
