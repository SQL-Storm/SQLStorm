SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  ARRAY_AGG(DISTINCT tag.Name) AS Tags,
  COUNT(DISTINCT c.Id) AS CommentCount,
  SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
  SUM(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS CommunityOwnedEvents
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN LATERAL (
  SELECT TRIM(BOTH '<>' FROM elem) AS Name
  FROM UNNEST(string_to_array(COALESCE(p.Tags, ''), '><')) AS t(elem)
) tag ON TRUE
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Posts related_post ON related_post.Id = pl.RelatedPostId
LEFT JOIN Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.DisplayName,
  u.Reputation
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;