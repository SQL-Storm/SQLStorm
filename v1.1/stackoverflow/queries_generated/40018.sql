-- {"query": "40018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 176} 

SELECT 
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT u.Id) AS TotalUsers,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(DISTINCT v.PostId) AS TotalVotes,
    SUM(p.Score) AS TotalScore,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MIN(u.CreationDate) AS EarliestUserCreationDate,
    MAX(u.Reputation) AS MaxReputation,
    AVG(p.AnswerCount) AS AvgAnswersPerQuestion
FROM 
    Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId;
