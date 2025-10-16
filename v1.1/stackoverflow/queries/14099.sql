-- {"query": "14099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 233500, "output_tokens": 101724} 
WITH cte AS (
  SELECT 
    p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.OwnerUserId, p.LastActivityDate, 
    u.Reputation, u.CreationDate AS UserCreationDate, u.UpVotes, u.DownVotes, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    COUNT(c.Id) AS CommentCount
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  LEFT JOIN Comments c ON p.Id = c.PostId  
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  GROUP BY p.Id, p.PostTypeId, p.ParentId, p.CreationDate, p.Score, p.OwnerUserId, p.LastActivityDate, 
           u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes
)
SELECT
  c1.Id AS PostId, 
  c1.PostTypeId, 
  c1.ParentId,
  c1.CreationDate,
  c1.Score,
  c1.OwnerUserId,
  c1.LastActivityDate,
  c1.Reputation,
  c1.UserCreationDate,
  c1.UpVotes,
  c1.DownVotes,
  c1.UpVoteCount,
  c1.DownVoteCount,
  c1.CommentCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = c1.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = c1.Id AND pl.LinkTypeId = 1) AS LinkCount,
  CASE WHEN c1.PostTypeId = 1 THEN 
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = c1.Id AND p2.PostTypeId = 2)
  ELSE 0 END AS AnswerCount
FROM cte c1
LEFT JOIN cte c2 ON c1.ParentId = c2.Id
ORDER BY c1.LastActivityDate DESC;