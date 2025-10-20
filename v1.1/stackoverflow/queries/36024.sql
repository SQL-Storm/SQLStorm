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
  ARRAY_AGG(DISTINCT tgs.TagName) FILTER (WHERE p.PostTypeId = 1) AS TagsList
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN (
  SELECT p2.Id AS PostId, tag AS TagName
  FROM Posts p2,
       UNNEST(string_to_array(SUBSTR(p2.Tags, 2, LENGTH(p2.Tags) - 2), '><')) AS tag
  WHERE p2.PostTypeId = 1
) AS tgs ON tgs.PostId = p.Id
LEFT JOIN Tags t ON t.ExcerptPostId = p.Id
GROUP BY p.Id, p.Title, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName
HAVING COUNT(c.Id) > 0
ORDER BY NetVotes DESC, p.CreationDate DESC
LIMIT 100;