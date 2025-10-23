-- {"query": "358.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 22629} 
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
    AND p.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days')
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
  COALESCE(array_to_string(string_to_array(substring(TagField, 2, length(TagField) - 2), '><'), ', '), '') AS TagList
FROM Ranked
WHERE OwnerRank <= 5
UNION ALL
SELECT
  NULL::int AS PostId,
  'Summary' AS Title,
  NULL::smallint AS PostTypeId,
  cast('2024-10-01 12:34:56' as timestamp)::timestamp AS CreationDate,
  CAST(AVG(Score) AS int) AS Score,
  NULL::int AS ViewCount,
  'System' AS OwnerName,
  NULL::int AS OwnerRank,
  NULL::int AS LinkCount,
  NULL::int AS CommentCount,
  NULL::int AS UpVotes,
  NULL::int AS DownVotes,
  '' AS TagList
FROM Ranked
ORDER BY 7, 8;