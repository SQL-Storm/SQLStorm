-- {"query": "32018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 364} 

SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COALESCE(SUM(v.VoteTypeId = 2), 0) AS TotalUpVotes, 
    COALESCE(SUM(v.VoteTypeId = 3), 0) AS TotalDownVotes, 
    b.TotalBadges, 
    EXTRACT(YEAR FROM age(CURRENT_TIMESTAMP, u.CreationDate)) AS MembershipYears
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
LEFT JOIN 
    (
        SELECT 
            UserId, 
            COUNT(Id) AS TotalBadges 
        FROM 
            Badges 
        GROUP BY 
            UserId
    ) b ON u.Id = b.UserId
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, b.TotalBadges, u.CreationDate
HAVING 
    COUNT(p.Id) > 1000 
    AND SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 500
    AND SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 500
ORDER BY 
    u.Reputation DESC, TotalPosts DESC, TotalQuestions DESC, MembershipYears DESC;
