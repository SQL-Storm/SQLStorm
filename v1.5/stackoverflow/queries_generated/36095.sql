-- {"query": "36095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 450} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.OwnerUserId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  p.AnswerCount,
  p.Tags,
  p.LastActivityDate,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.Location,
  u.AboutMe,
  COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesReceived,
  COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesReceived,
  AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.OwnerUserId) AS AvgUpVotesPerPostByOwner,
  (SELECT AVG(ViewCount) FROM Posts WHERE OwnerUserId = p.OwnerUserId) AS AvgPostViewsByOwner,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicatesCount,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = p.Id) AS TotalVotesOnPost
FROM
  Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  p.PostTypeId IN (1, 2) -- include questions and answers
  AND p.CreationDate >= NOW() - INTERVAL '365 days'
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.OwnerUserId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  p.AnswerCount,
  p.Tags,
  p.LastActivityDate,
  u.Reputation,
  u.CreationDate,
  u.Location,
  u.AboutMe
ORDER BY
  p.Score DESC,
  p.ViewCount DESC
LIMIT 100;