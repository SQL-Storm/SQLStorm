-- {"query": "314.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 14224} 
WITH
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    'Question' AS PostTypeName,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    COALESCE(u.DisplayName, p.OwnerDisplayName, 'Unknown') AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    p.AnswerCount,
    p.CommentCount,
    p.ParentId,
    p.LastEditDate,
    p.LastEditorDisplayName,
    p.LastEditorUserId,
    CASE
      WHEN p.Tags IS NULL OR LENGTH(p.Tags) <= 2 THEN 0
      ELSE (SELECT COUNT(*) FROM UNNEST(string_to_array(substr(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS t)
    END AS TagCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days')
    AND p.Score > 0
),
TopQuestionsFiltered AS (
  SELECT *
  FROM TopQuestions
  WHERE rn <= 200
),
TopAnswers AS (
  SELECT
    a.Id AS PostId,
    'Answer' AS PostTypeName,
    NULL AS Title,
    NULL AS Tags,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    COALESCE(uu.DisplayName, a.OwnerDisplayName, 'Unknown') AS OwnerDisplayName,
    uu.Reputation AS OwnerReputation,
    a.AnswerCount,
    a.CommentCount,
    a.ParentId,
    a.LastEditDate,
    a.LastEditorDisplayName,
    a.LastEditorUserId,
    0 AS TagCount,
    ROW_NUMBER() OVER (PARTITION BY a.PostTypeId ORDER BY a.Score DESC, a.CreationDate DESC) AS rn
  FROM Posts a
  LEFT JOIN Users uu ON a.OwnerUserId = uu.Id
  WHERE a.PostTypeId = 2
    AND a.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days')
),
TopAnswersFiltered AS (
  SELECT *
  FROM TopAnswers
  WHERE rn <= 200
),
UnionAllSet AS (
  SELECT
     PostId, PostTypeName, Title, Tags, CreationDate, LastActivityDate, Score, ViewCount, OwnerUserId, OwnerDisplayName, OwnerReputation, AnswerCount, CommentCount, ParentId, LastEditDate, LastEditorDisplayName, LastEditorUserId, TagCount
  FROM TopQuestionsFiltered
  UNION ALL
  SELECT
     PostId, PostTypeName, Title, Tags, CreationDate, LastActivityDate, Score, ViewCount, OwnerUserId, OwnerDisplayName, OwnerReputation, AnswerCount, CommentCount, ParentId, LastEditDate, LastEditorDisplayName, LastEditorUserId, TagCount
  FROM TopAnswersFiltered
)
SELECT
  PostId,
  PostTypeName,
  Title,
  Tags,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  OwnerUserId,
  OwnerDisplayName,
  OwnerReputation,
  AnswerCount,
  CommentCount,
  ParentId,
  LastEditDate,
  LastEditorDisplayName,
  LastEditorUserId,
  TagCount
FROM UnionAllSet
ORDER BY PostTypeName, Score DESC
LIMIT 100;