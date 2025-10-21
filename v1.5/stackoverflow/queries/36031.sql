SELECT
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2, 3)) AS NetVotes,
  STRING_AGG(DISTINCT ta.TagName, ',') AS Tags,
  COUNT(DISTINCT c.Id) AS CommentCount,
  MAX(pl.CreationDate) AS LastLinkCreationDate,
  MAX(p.LastActivityDate) AS LastActivity
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT DISTINCT
    t.value AS TagName
  FROM (
    SELECT UNNEST(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ',')) AS value
  ) AS t
) AS ta ON TRUE
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
GROUP BY
  p.Id,
  p.PostTypeId,
  p.Title,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.OwnerUserId,
  u.DisplayName
ORDER BY
  p.CreationDate DESC
LIMIT 100;