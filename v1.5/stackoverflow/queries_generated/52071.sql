-- {"query": "52071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 351} 
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(v.TotalUpvotes, 0) AS TotalUpvotesOnPosts,
    COALESCE(p.AvgQuestionScore, 0) AS AvgQuestionScore,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    (u.Reputation + COALESCE(b.GoldBadges, 0) * 1000 + COALESCE(v.TotalUpvotes, 0) * 10 + COALESCE(p.AvgQuestionScore, 0) * 5 + COALESCE(p.AnswerCount, 0) * 2) AS CompositeScore
FROM 
    Users u
LEFT JOIN 
    (SELECT 
         UserId, 
         COUNT(*) AS GoldBadges 
     FROM 
         Badges 
     WHERE 
         Class = 1 
     GROUP BY 
         UserId) b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
         OwnerUserId, 
         SUM(Score) AS TotalUpvotes 
     FROM 
         Posts 
     GROUP BY 
         OwnerUserId) v ON u.Id = v.OwnerUserId
LEFT JOIN 
    (SELECT 
         OwnerUserId, 
         AVG(Score) AS AvgQuestionScore, 
         COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCount 
     FROM 
         Posts 
     WHERE 
         PostTypeId = 1 
     GROUP BY 
         OwnerUserId) p ON u.Id = p.OwnerUserId
ORDER BY 
    CompositeScore DESC
LIMIT 100;