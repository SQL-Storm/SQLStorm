SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.ViewCount,
  p.Score,
  p.CreationDate,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
  COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
  COUNT(DISTINCT cl.Id) AS CommentCount,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE p.PostTypeId = 1) AS Tags,
  MAX(CASE WHEN ph.PostHistoryTypeId = 50 THEN ph.CreationDate END) AS CommunityBumpDate,
  MAX(p.LastActivityDate) AS LastActivityDate
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments cl ON cl.PostId = p.Id
  LEFT JOIN LATERAL (
    SELECT DISTINCT t.TagName
    FROM UNNEST(string_to_array(TRIM(BOTH '><' FROM p.Tags), '><')) AS t(TagName)
  ) AS t ON TRUE
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
WHERE
  p.PostTypeId IN (1, 2)
  AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY)
GROUP BY
  p.Id,
  p.Title,
  p.PostTypeId,
  p.ViewCount,
  p.Score,
  p.CreationDate,
  p.OwnerUserId,
  u.DisplayName
ORDER BY
  p.Score DESC,
  p.ViewCount DESC
LIMIT 100;