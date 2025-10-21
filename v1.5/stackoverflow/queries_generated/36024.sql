-- {"query": "36024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 364} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(c.Id) AS CommentCount,
  MAX(v.CreationDate) AS LastVoteDate,
  SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS NetVotes,
  STRING_AGG(pt.Name, ',') FILTER (WHERE p.PostTypeId = 1) AS RelatedPostTypes,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE p.PostTypeId = 1) AS TagsList
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN (SELECT PostId, TagName
           FROM Posts p2
           JOIN UNNEST(string_to_array(substr(p2.Tags, 2, length(p2.Tags) - 2), '><')) AS TagName ON TRUE
           WHERE p2.PostTypeId = 1) AS tgs ON tgs.PostId = p.Id
LEFT JOIN Tags t ON t.ExcerptPostId = p.Id
GROUP BY p.Id, p.Title, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName
HAVING COUNT(c.Id) > 0
ORDER BY NetVotes DESC NULLS LAST, p.CreationDate DESC
LIMIT 100;