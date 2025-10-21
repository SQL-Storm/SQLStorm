-- {"query": "394.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20996} 
WITH
Questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Body,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.PostTypeId = 1
),
QuestionsWithOwners AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.Score,
    q.ViewCount,
    q.CreationDate,
    q.LastActivityDate,
    q.Body,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    lu.DisplayName AS LastEditorDisplayName,
    lu.Reputation AS LastEditorReputation,
    q.LastEditDate
  FROM Questions q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN Users lu ON q.LastEditorUserId = lu.Id
),
Answered AS (
  SELECT a.ParentId AS PostId, COUNT(*) AS AnswerCount, AVG(COALESCE(a.Score, 0)) AS AvgAnswerScore
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
Final AS (
  SELECT qw.PostId,
         qw.Title,
         qw.Tags,
         qw.Score,
         qw.ViewCount,
         qw.CreationDate,
         qw.LastActivityDate,
         qw.Body,
         qw.OwnerDisplayName,
         qw.OwnerReputation,
         qw.LastEditorDisplayName,
         qw.LastEditorReputation,
         qw.LastEditDate,
         COALESCE(an.AnswerCount, 0) AS AnswerCount,
         COALESCE(an.AvgAnswerScore, 0) AS AvgAnswerScore,
         array_length(string_to_array(substring(qw.Tags, 2, length(qw.Tags) - 2), '><'), 1) AS TagCount,
         array_to_string(string_to_array(substring(qw.Tags, 2, length(qw.Tags) - 2), '><'), ',') AS TagList,
         1 AS Source
  FROM QuestionsWithOwners qw
  LEFT JOIN Answered an ON an.PostId = qw.PostId
  WHERE qw.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
),
Recent AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Body,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    lu.DisplayName AS LastEditorDisplayName,
    lu.Reputation AS LastEditorReputation,
    p.LastEditDate,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
    (SELECT AVG(COALESCE(a.Score,0)) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AvgAnswerScore,
    array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1) AS TagCount,
    array_to_string(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), ',') AS TagList,
    2 AS Source
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users lu ON p.LastEditorUserId = lu.Id
  WHERE p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
  ORDER BY p.LastActivityDate DESC
  LIMIT 50
)
SELECT AllPosts.PostId,
       AllPosts.Title,
       AllPosts.Tags,
       AllPosts.Score,
       AllPosts.ViewCount,
       AllPosts.CreationDate,
       AllPosts.LastActivityDate,
       AllPosts.Body,
       AllPosts.OwnerDisplayName,
       AllPosts.OwnerReputation,
       AllPosts.LastEditorDisplayName,
       AllPosts.LastEditorReputation,
       AllPosts.LastEditDate,
       AllPosts.AnswerCount,
       AllPosts.AvgAnswerScore,
       AllPosts.TagCount,
       AllPosts.TagList,
       AllPosts.Source,
       ROW_NUMBER() OVER (ORDER BY AllPosts.Score DESC, AllPosts.ViewCount DESC, AllPosts.LastActivityDate DESC) AS Rank
FROM (
  SELECT *
  FROM Final
  UNION ALL
  SELECT *
  FROM Recent
) AS AllPosts
ORDER BY Rank
LIMIT 200;