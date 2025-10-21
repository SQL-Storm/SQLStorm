-- {"query": "30082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 82} 
SELECT Posts.Title, Users.DisplayName, Votes.VoteTypeId, COUNT(*) as VoteCount
FROM Posts
JOIN Users ON Users.Id = Posts.OwnerUserId
JOIN Votes ON Votes.PostId = Posts.Id
WHERE Votes.VoteTypeId IN (2, 3) /* UpMod and DownMod */
GROUP BY Posts.Title, Users.Id, Users.DisplayName, Votes.VoteTypeId
ORDER BY VoteCount DESC;