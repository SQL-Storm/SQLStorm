WITH Ranked AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId AS OwnerId,
    COALESCE(u.DisplayName, 'Unknown') AS OwnerName,
    p.Tags AS TagField,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS OwnerRank,
    COALESCE((SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id), 0) AS LinkCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days')
)
SELECT
  PostId,
  Title,
  PostTypeId,
  CreationDate,
  Score,
  ViewCount,
  OwnerName,
  OwnerRank,
  LinkCount,
  CommentCount,
  UpVotes,
  DownVotes,
  COALESCE(
    ARRAY_TO_STRING(
      STRING_TO_ARRAY(SUBSTR(TagField, 2, LENGTH(TagField) - 2), '><'),
      ', '
    ),
    ''
  ) AS TagList
FROM Ranked
WHERE OwnerRank <= 5
UNION ALL
SELECT
  NULL AS PostId,
  'Summary' AS Title,
  NULL AS PostTypeId,
  CAST('2024-10-01 12:34:56' AS TIMESTAMP) AS CreationDate,
  CAST(AVG(Score) AS INTEGER) AS Score,
  NULL AS ViewCount,
  'System' AS OwnerName,
  NULL AS OwnerRank,
  NULL AS LinkCount,
  NULL AS CommentCount,
  NULL AS UpVotes,
  NULL AS DownVotes,
  '' AS TagList
FROM Ranked
ORDER BY 7, 8;