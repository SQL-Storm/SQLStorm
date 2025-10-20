-- {"query": "36030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 316} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.LastActivityDate,
  COUNT(DISTINCT v.Id) AS VoteCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id) AS LinkedFromCount,
  (SELECT COUNT(*) FROM ViewCounts vc WHERE vc.PostId = p.Id) AS DailyViews,
  p.Tags,
  p.AcceptedAnswerId
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, p.LastActivityDate, p.Tags, p.AcceptedAnswerId
ORDER BY
  p.CreationDate DESC
LIMIT 100;