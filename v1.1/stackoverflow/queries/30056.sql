-- {"query": "30056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 54} 
SELECT Posts.Id, Posts.Title, Users.DisplayName, Posts.Score, Votes.VoteTypeId
FROM Posts
JOIN Users ON Posts.OwnerUserId = Users.Id
LEFT JOIN Votes ON Posts.Id = Votes.PostId
ORDER BY Posts.Score DESC, Votes.VoteTypeId ASC;