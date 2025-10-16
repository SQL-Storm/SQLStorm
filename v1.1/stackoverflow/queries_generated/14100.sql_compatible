WITH cte AS (
  SELECT p.Id, p.Title, p.Body, p.Tags, p.OwnerUserId, p.CreationDate, 
         DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
), top_posts AS (
  SELECT Id, Title, Body, Tags, OwnerUserId, CreationDate
  FROM cte
  WHERE rn <= 10
)
SELECT 
  p.Id, 
  p.Title,
  CONCAT(SUBSTRING(p.Body FROM 1 FOR 100), '...') AS Body_Snippet,
  CONCAT('[', REPLACE(p.Tags, '<', ''), ']') AS Tags,
  u.DisplayName AS OwnerName,
  CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
  CASE 
    WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'Duplicate'
    WHEN EXISTS (SELECT 1 FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId = 6) THEN 'Closed'
    WHEN EXISTS (SELECT 1 FROM Votes v3 WHERE v3.PostId = p.Id AND v3.VoteTypeId = 7) THEN 'Reopened'
    ELSE 'Open'
  END AS PostStatus,
  COALESCE(NULLIF(
    -- extract first tag between > and <
    regexp_replace(
      split_part(p.Tags, '><', 1),
      '^.*?>',
      ''
    ),
    ''
  ), 'None') AS PrimaryTag,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
  COALESCE(COUNT(c.Id), 0) AS CommentCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.Id IN (SELECT Id FROM top_posts)
GROUP BY p.Id, p.Title, p.Body, p.Tags, u.DisplayName, p.CreationDate
ORDER BY DaysSinceCreation DESC
LIMIT 50;