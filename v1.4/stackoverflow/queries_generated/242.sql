-- {"query": "242.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 12411} 
WITH
TagArrayQA AS (
  SELECT p.Id AS PostId,
         CASE WHEN p.Tags IS NULL THEN ARRAY[]::text[]
              ELSE string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')
         END AS Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
),
VotesAS AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Votes v
  GROUP BY v.PostId
)
SELECT *
FROM (
  SELECT
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    ta.Tags AS Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Posts aa WHERE aa.ParentId = p.Id AND aa.PostTypeId = 2) AS AnswerCount,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    (p.AcceptedAnswerId IS NOT NULL) AS HasAcceptedAnswer,
    CASE WHEN p.Score > 50 AND p.ViewCount > 5000 THEN 'hot' ELSE 'normal' END AS Status,
    p.LastEditorDisplayName AS LastEditorDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerQuestionRank
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN TagArrayQA ta ON ta.PostId = p.Id
  LEFT JOIN VotesAS va ON va.PostId = p.Id
  WHERE p.PostTypeId = 1
  UNION ALL
  SELECT
    p.Id AS PostId,
    p.Title,
    NULL::text AS OwnerDisplayName,
    NULL::int AS OwnerReputation,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    NULL::text[] AS Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Posts aa WHERE aa.ParentId = p.Id AND aa.PostTypeId = 2) AS AnswerCount,
    COALESCE((SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id), 0) AS UpVotes,
    COALESCE((SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id), 0) AS DownVotes,
    FALSE AS HasAcceptedAnswer,
    NULL::text AS Status,
    NULL::text AS LastEditorDisplayName,
    NULL::int AS OwnerQuestionRank
  FROM Posts p
  WHERE p.PostTypeId = 2
) AS Combined
ORDER BY Score DESC NULLS LAST
LIMIT 500;