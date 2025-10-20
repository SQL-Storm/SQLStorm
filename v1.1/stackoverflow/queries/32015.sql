-- {"query": "32015.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 304} 
SELECT 
    u.DisplayName,
    SUM(CASE WHEN bt.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN bt.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN bt.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(p.Score) AS TotalPostScore,
    SUM(c.Score) AS TotalCommentScore
FROM 
    Users u
LEFT JOIN 
    Badges bt ON u.Id = bt.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    GoldBadges DESC, 
    SilverBadges DESC, 
    BronzeBadges DESC, 
    UpVotesReceived DESC;