-- {"query": "6657.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 452} 
SELECT 
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    MAX(u.Reputation) AS MaxReputation,
    MIN(u.CreationDate) AS EarliestUserCreation,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS PopularPosts,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 19, 20, 35)
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Id IN (
        SELECT 
            UserId
        FROM 
            Votes
        WHERE 
            VoteTypeId = 2 AND CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 month'
    )
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    AVG(p.Score) > 100
ORDER BY 
    TotalPosts DESC, MaxReputation DESC;