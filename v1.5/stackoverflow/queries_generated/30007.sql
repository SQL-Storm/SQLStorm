-- {"query": "30007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 64} 

SELECT Posts.Id, Posts.Title, SUM(Votes.BountyAmount) AS TotalBounty
FROM Posts
LEFT JOIN Votes ON Posts.Id = Votes.PostId
WHERE Posts.PostTypeId = 1
GROUP BY Posts.Id, Posts.Title
ORDER BY TotalBounty DESC
LIMIT 10;
