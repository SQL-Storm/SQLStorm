-- {"query": "32066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 367} 
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT p.Id) AS TotalPosts, 
    COUNT(distinct c.Id) AS TotalComments, 
    SUM(COALESCE(vVoteCnt.UpVotes, 0)) AS TotalUpVotes, 
    SUM(COALESCE(vVoteCnt.DownVotes, 0)) AS TotalDownVotes, 
    SUM(COALESCE(b.BadgeCount, 0)) AS TotalBadges, 
    AVG(COALESCE(p.Score, 0)) AS AveragePostScore
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    (SELECT 
         v.PostId, 
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
     FROM 
         Votes v
     GROUP BY 
         v.PostId) AS vVoteCnt ON p.Id = vVoteCnt.PostId
LEFT JOIN 
    (SELECT 
         b.UserId, 
         COUNT(*) AS BadgeCount
     FROM 
         Badges b
     GROUP BY 
         b.UserId) AS b ON u.Id = b.UserId
WHERE 
    u.CreationDate >= '2020-01-01' 
AND 
    u.LastAccessDate <= cast('2024-10-01 12:34:56' as timestamp)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    TotalPosts DESC, TotalUpVotes DESC
LIMIT 50;