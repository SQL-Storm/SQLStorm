-- {"query": "32026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 456} 

SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND v.VoteTypeId = 2 THEN v.Id END) AS AnswerUpvotes,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND v.VoteTypeId = 3 THEN v.Id END) AS AnswerDownvotes,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    COUNT(DISTINCT CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN p.Id END) AS CommunityWikiPosts,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AverageQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AverageAnswerScore,
    MAX(p.CreationDate) - MIN(p.CreationDate) AS UserPostSpan
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.CreationDate >= '2020-01-01' 
    AND u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalQuestionScore DESC, TotalAnswerScore DESC, GoldBadges DESC, SilverBadges DESC, BronzeBadges DESC
LIMIT 100;
