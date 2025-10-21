SELECT 
    u.DisplayName,
    u.Reputation,
    COALESCE(SUM(p.Score), 0) AS TotalScore,
    COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalComments,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END), 0) AS TotalAnswers,
    COALESCE(COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END), 0) AS TotalUpvotes,
    COALESCE(COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END), 0) AS TotalDownvotes,
    COALESCE(COUNT(DISTINCT b.Id), 0) AS TotalBadges,
    CASE
        WHEN COUNT(DISTINCT b.Id) = 0 THEN 'Newbie'
        WHEN COUNT(DISTINCT b.Id) < 5 THEN 'Apprentice'
        WHEN COUNT(DISTINCT b.Id) < 10 THEN 'Journeyman'
        ELSE 'Master'
    END AS UserTitle
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON c.UserId = u.Id
LEFT JOIN 
    Votes v ON v.UserId = u.Id
LEFT JOIN 
    Badges b ON b.UserId = u.Id
WHERE 
    u.CreationDate >= DATE '2021-01-01'
GROUP BY 
    u.DisplayName,
    u.Reputation,
    u.Id
ORDER BY 
    TotalScore DESC,
    TotalComments DESC,
    TotalAnswers DESC,
    TotalUpvotes DESC,
    TotalBadges DESC,
    u.LastAccessDate DESC
LIMIT 100;