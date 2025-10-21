-- {"query": "44029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 66526, "output_tokens": 25564} 

SELECT 
  p.Title, 
  p.Tags, 
  p.OwnerUserId, 
  u.DisplayName AS OwnerDisplayName, 
  p.CreationDate, 
  p.LastEditDate, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.FavoriteCount, 
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
  (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id) AS PostHistoryCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS PostLinkCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
ORDER BY p.Score DESC
LIMIT 100;
```

This query retrieves the top 100 questions from the StackOverflow database based on their score, and includes various performance-related metrics such as view count, answer count, favorite count, comment count, upvote count, downvote count, post history count, and post link count. The query joins the Posts and Users tables to fetch the owner's display name, and filters the results to only include questions (PostTypeId = 1).