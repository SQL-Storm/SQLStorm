-- {"query": "52067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 341} 
SELECT 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    SUM(p.Score) AS TotalPostScore,
    AVG(p.Score) AS AvgPostScore,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadgeCount,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, COUNT(DISTINCT c.Id) DESC, COUNT(DISTINCT v.Id) DESC) AS ActivityRank
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.CreationDate >= '2008-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0 OR COUNT(DISTINCT c.Id) > 0 OR COUNT(DISTINCT v.Id) > 0
ORDER BY ActivityRank ASC
LIMIT 500;