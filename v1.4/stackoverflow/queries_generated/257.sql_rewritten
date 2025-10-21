-- {"query": "257.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 7565} 
WITH
tag_lists AS (
  SELECT
    p.Id AS PostId,
    COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1), 0) AS TagCount
  FROM Posts p
  WHERE p.Tags IS NOT NULL
),
edits AS (
  SELECT PostId, COUNT(*) AS EditCount
  FROM PostHistory
  WHERE PostHistoryTypeId IN (4,5,6,8,9,24,50,52,53)
  GROUP BY PostId
),
dup AS (
  SELECT PostId, COUNT(*) AS DuplicateCount
  FROM PostLinks
  WHERE LinkTypeId = 3
  GROUP BY PostId
),
recent_question AS (
  SELECT
    'Q' AS Kind,
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    u.DisplayName AS Owner,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    COALESCE(e.EditCount, 0) AS EditCount,
    COALESCE(d.DuplicateCount, 0) AS DuplicateCount,
    COALESCE(t.TagCount, 0) AS TagCount
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN edits e ON e.PostId = p.Id
  LEFT JOIN dup d ON d.PostId = p.Id
  LEFT JOIN tag_lists t ON t.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '180 days'
),
recent_answers AS (
  SELECT
    'A' AS Kind,
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    u.DisplayName AS Owner,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    COALESCE(e.EditCount, 0) AS EditCount,
    COALESCE(d.DuplicateCount, 0) AS DuplicateCount,
    COALESCE(t.TagCount, 0) AS TagCount
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN edits e ON e.PostId = p.Id
  LEFT JOIN dup d ON d.PostId = p.Id
  LEFT JOIN tag_lists t ON t.PostId = p.Id
  WHERE p.PostTypeId = 2
    AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '180 days'
),
union_all AS (
  SELECT * FROM recent_question
  UNION ALL
  SELECT * FROM recent_answers
)
SELECT
  Kind,
  PostId,
  Title,
  PostTypeId,
  OwnerUserId,
  Owner,
  Score,
  ViewCount,
  CreationDate,
  EditCount,
  DuplicateCount,
  TagCount,
  ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY Score DESC, ViewCount DESC) AS TypeRank,
  (Score * 4) + (ViewCount * 2) + (TagCount * 8) AS BenchmarkScore,
  (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = union_all.OwnerUserId) AS AvgScoreByOwner
FROM union_all
ORDER BY PostTypeId, TypeRank
LIMIT 500;