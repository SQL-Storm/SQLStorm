-- {"query": "30098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 89} 

SELECT Posts.Title, Users.DisplayName, Posts.Score, Comments.Score AS CommentScore, Votes.CreationDate
FROM Posts
JOIN Users ON Posts.OwnerUserId = Users.Id
LEFT JOIN Comments ON Posts.Id = Comments.PostId
LEFT JOIN Votes ON Posts.Id = Votes.PostId
WHERE Posts.PostTypeId = 1
ORDER BY Posts.Score DESC, Comments.Score DESC, Votes.CreationDate DESC
LIMIT 1000;
