SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes, 
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes, 
    b.TotalBadges, 
    EXTRACT(YEAR FROM age(CAST('2024-10-01 12:34:56' AS timestamp), u.CreationDate)) AS MembershipYears
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