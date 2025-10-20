-- {"query": "400.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 16593} 
WITH
PostMetrics AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COALESCE(p.OwnerDisplayName, u.DisplayName, 'Unknown') AS OwnerName,
    p.LastEditDate,
    p.LastActivityDate,
    CASE
      WHEN p.Tags IS NULL THEN 0
      WHEN length(p.Tags) < 3 THEN 0
      ELSE COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1), 0)
    END AS TagCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT MAX(CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id) AS LastHistoryDate,
    (SELECT COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0)
     FROM Votes v WHERE v.PostId = p.Id) AS NetVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  WHERE p.CreationDate >= (CURRENT_DATE - INTERVAL '180 days')
),
Ranked AS (
  SELECT
    PostId, PostTypeId, PostTypeName, Title, Tags, CreationDate, Score, ViewCount, OwnerName, LastEditDate, LastActivityDate,
    TagCount, CommentCount, LastHistoryDate, NetVotes,
    ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY NetVotes DESC, Score DESC, TagCount DESC) AS rn
  FROM PostMetrics
),
TopSets AS (
  SELECT * FROM Ranked WHERE PostTypeId = 1 AND rn <= 200
  UNION ALL
  SELECT * FROM Ranked WHERE PostTypeId = 2 AND rn <= 200
),
Final AS (
  SELECT
    PostId,
    PostTypeId,
    PostTypeName,
    Title,
    Tags,
    TagCount,
    CreationDate,
    Score,
    ViewCount,
    OwnerName,
    LastEditDate,
    LastActivityDate,
    CommentCount,
    LastHistoryDate,
    NetVotes,
    rn
  FROM TopSets
)
SELECT
  PostId,
  PostTypeName,
  OwnerName,
  Title,
  TagCount,
  CASE WHEN TagCount > 0 THEN '[' || ARRAY_TO_STRING(string_to_array(substring(Tags, 2, length(Tags) - 2), '><'), ', ') || ']' ELSE NULL END AS TagList,
  CreationDate,
  Score,
  ViewCount,
  LastEditDate,
  LastActivityDate,
  CommentCount,
  LastHistoryDate,
  NetVotes
FROM Final
ORDER BY NetVotes DESC, Score DESC
LIMIT 500;