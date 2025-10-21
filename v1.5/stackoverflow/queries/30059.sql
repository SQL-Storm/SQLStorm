-- {"query": "30059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 58} 
SELECT Users.DisplayName, COUNT(DISTINCT Posts.Id) AS NumPosts
FROM Users
JOIN Posts ON Users.Id = Posts.OwnerUserId
JOIN Votes ON Posts.Id = Votes.PostId
WHERE Votes.VoteTypeId = 2
GROUP BY Users.DisplayName
ORDER BY NumPosts DESC;