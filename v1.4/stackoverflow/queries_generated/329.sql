-- {"query": "329.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 18491} 
WITH
Questions AS (
  SELECT
    p.Id AS Id,
    p.Title AS Title,
    p.Tags AS Tags,
    p.Score AS Score,
    p.ViewCount AS ViewCount,
    p.CreationDate AS CreationDate,
    p.OwnerUserId AS OwnerUserId,
    COALESCE(p.OwnerDisplayName, 'Unknown') AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.CreationDate AS OwnerCreationDate
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate > now() - interval '365 days'
),
QuestionsEnrich AS (
  SELECT
    q.Id, q.Title, q.Tags, q.Score, q.ViewCount, q.CreationDate,
    q.OwnerUserId, q.OwnerDisplayName, q.OwnerReputation, q.OwnerCreationDate,
    CASE
      WHEN q.Tags IS NULL THEN 0
      ELSE array_length(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><'), 1)
    END AS TagCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCountCorrelated
  FROM Questions q
),
Answers AS (
  SELECT
    a.Id, a.Title, a.ParentId, a.Score, a.ViewCount, a.CreationDate,
    a.OwnerUserId, COALESCE(a.OwnerDisplayName, 'Unknown') AS OwnerDisplayName,
    u.Reputation AS OwnerReputation, u.CreationDate AS OwnerCreationDate
  FROM Posts a
  LEFT JOIN Users u ON a.OwnerUserId = u.Id
  WHERE a.PostTypeId = 2
    AND a.CreationDate > now() - interval '365 days'
),
Combined AS (
  SELECT
    'Question' AS Type,
    q.Id,
    COALESCE(q.Title, '') AS Title,
    (COALESCE(q.OwnerDisplayName, 'Unknown') || ' [' || COALESCE(CAST(q.OwnerReputation AS text), 'N/A') || ']') AS Owner,
    q.Score AS Score,
    q.ViewCount AS ViewCount,
    q.TagCount AS TagCount,
    q.CommentCountCorrelated AS CommentCount,
    q.OwnerCreationDate AS OwnerSince,
    q.CreationDate
  FROM QuestionsEnrich q
  UNION ALL
  SELECT
    'Answer' AS Type,
    a.Id,
    COALESCE(a.Title, '') AS Title,
    (COALESCE(a.OwnerDisplayName, 'Unknown') || ' [' || COALESCE(CAST(a.OwnerReputation AS text), 'N/A') || ']') AS Owner,
    a.Score AS Score,
    a.ViewCount AS ViewCount,
    0 AS TagCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS CommentCount,
    a.OwnerCreationDate AS OwnerSince,
    a.CreationDate
  FROM Answers a
),
Ranked AS (
  SELECT c.*,
         ROW_NUMBER() OVER (ORDER BY Score DESC NULLS LAST, ViewCount DESC NULLS LAST) AS rn
  FROM Combined c
)
SELECT *
FROM Ranked
WHERE rn <= 100
ORDER BY rn;