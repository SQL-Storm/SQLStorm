-- {"query": "6260.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 374} 

SELECT 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestJoinDate,
    MAX(CASE WHEN b.TagBased = 0 THEN b.Date END) AS FirstNonTagBadgeDate,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Tags ELSE NULL END, ',') WITHIN GROUP AS (ORDER BY p.CreationDate) AS QuestionTags,
    AVG(ph.Score) AS AvgCommentScore
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.Id IN (
        SELECT UserId 
        FROM Votes 
        WHERE VoteTypeId IN (1, 2, 3) 
        GROUP BY UserId 
        HAVING COUNT(DISTINCT PostId) > 10
    )
    AND p.CreationDate >= DATEADD(year, -5, CURRENT_TIMESTAMP)
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 20
ORDER BY 
    MaxReputation DESC, 
    TotalPosts DESC;
