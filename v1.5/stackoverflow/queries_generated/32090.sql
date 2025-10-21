-- {"query": "32090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 296} 

SELECT u.Id AS UserId, u.DisplayName, u.Reputation, 
       COUNT(DISTINCT p.Id) AS TotalPosts, 
       COALESCE(SUM(p.ViewCount), 0) AS TotalViews, 
       COALESCE(SUM(p.Score), 0) AS TotalScore, 
       COUNT(DISTINCT b.Id) AS TotalBadges 
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount 
    FROM Comments 
    GROUP BY PostId
) c ON p.Id = c.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS AnswerCount 
    FROM Posts 
    WHERE PostTypeId = 2
    GROUP BY PostId
) a ON p.Id = a.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount, 
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes 
    GROUP BY PostId
) v ON p.Id = v.PostId
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY TotalScore DESC, TotalViews DESC
LIMIT 50;
