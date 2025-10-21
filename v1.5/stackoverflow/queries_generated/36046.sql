-- {"query": "36046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 349} 
SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(v.Id) AS TotalVotes,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  COUNT(c.Id) AS CommentCount,
  MAX(CASE WHEN c.CreationDate IS NOT NULL THEN c.CreationDate END) AS LastCommentDate,
  COUNT(br.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
  COUNT(br.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
  COUNT(br.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Badges br ON br.UserId = p.OwnerUserId
GROUP BY
  p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, u.DisplayName
HAVING
  p.CreationDate >= NOW() - INTERVAL '30 days'
ORDER BY
  p.Score DESC, p.ViewCount DESC
LIMIT 100;