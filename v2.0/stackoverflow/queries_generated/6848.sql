-- {"query": "6848.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 540} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.ClosedDate IS NOT NULL) AS TotalClosedPosts,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.CommunityOwnedDate IS NOT NULL) AS TotalCommunityOwnedPosts,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN u.Id ELSE NULL END) AS TotalBadges,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.Reputation) AS MinReputation,
    AVG(u.Reputation) AS AvgReputation,
    STRING_AGG(DISTINCT t.TagName, ', ') WITHIN GROUP (ORDER BY t.TagName) AS PopularTags,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS TotalUpVotes,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS TotalDownVotes
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Tags t ON p.Id = ANY(STRING_TO_ARRAY(p.Tags, '/><')::int[])
LEFT JOIN 
    (
        SELECT 
            ph.PostId,
            ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
        FROM 
            PostHistory ph
    ) ph ON p.Id = ph.PostId AND ph.rn = 1
WHERE 
    u.Id IN (
        SELECT 
            UserId
        FROM 
            Votes
        GROUP BY 
            UserId
        HAVING 
            COUNT(*) > 100
    )
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 50
ORDER BY 
    u.Reputation DESC;
