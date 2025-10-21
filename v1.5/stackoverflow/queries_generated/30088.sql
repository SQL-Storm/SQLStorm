-- {"query": "30088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 25} 
SELECT Posts.Id, Posts.Score, Votes.VoteTypeId 
FROM Posts
JOIN Votes ON Posts.Id = Votes.PostId;