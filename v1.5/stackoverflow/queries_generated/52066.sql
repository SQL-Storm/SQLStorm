-- {"query": "52066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 443} 
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(p.Score) AS TotalPostScore,
    SUM(p.ViewCount) AS TotalViewCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(v.UpVotes) AS TotalUpVotes,
    SUM(v.DownVotes) AS TotalDownVotes,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
    AVG(p.AnswerCount) AS AvgAnswerCount,
    MAX(p.CreationDate) AS LatestPostDate,
    MIN(p.CreationDate) AS EarliestPostDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
INNER JOIN 
    (SELECT 
         v.UserId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
     FROM 
         Votes v
     GROUP BY 
         v.UserId) v ON u.Id = v.UserId
WHERE 
    u.Reputation > 1000
    AND u.CreationDate >= '2008-01-01'::timestamp
    AND u.LastAccessDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
    AND COUNT(DISTINCT b.Id) > 5
ORDER BY 
    u.Reputation DESC, TotalPostScore DESC
LIMIT 100;