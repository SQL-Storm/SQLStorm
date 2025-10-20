-- {"query": "272.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6810} 
WITH
Base AS (
  SELECT p.Id AS PostId,
         p.OwnerUserId,
         p.Title,
         p.PostTypeId,
         p.Score,
         p.ViewCount,
         p.Tags,
         p.CreationDate,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.CreationDate > (NOW() - INTERVAL '1 year')
    AND p.PostTypeId IN (1, 2)
),
Metrics AS (
  SELECT b.PostId, b.OwnerUserId, b.Title, b.PostTypeId, b.Score, b.ViewCount, b.Tags, b.CreationDate, b.CommentCount,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         COALESCE(array_length(string_to_array(substring(b.Tags, 2, length(b.Tags) - 2), '><'), 1), 0) AS TagCount
  FROM Base b
  LEFT JOIN Votes v ON v.PostId = b.PostId
  GROUP BY b.PostId, b.OwnerUserId, b.Title, b.PostTypeId, b.Score, b.ViewCount, b.Tags, b.CreationDate, b.CommentCount
),
Enrich AS (
  SELECT m.PostId,
         m.OwnerUserId,
         u.DisplayName AS OwnerDisplayName,
         u.Reputation,
         COALESCE(u.Location, 'Unknown') AS Location,
         m.Title,
         m.PostTypeId,
         m.Score,
         m.ViewCount,
         m.CommentCount,
         m.UpVotes,
         m.DownVotes,
         m.TagCount,
         m.Tags,
         p.LastActivityDate AS LastActivityDate,
         p.LastEditorDisplayName AS LastEditorDisplayName,
         ROUND((m.Score * 2.0
                + m.ViewCount * 0.2
                + m.CommentCount * 1.2
                + m.UpVotes * 5
                - m.DownVotes * 2)
               / NULLIF((CASE WHEN m.TagCount > 0 THEN 1 + m.TagCount ELSE 1 END), 0)
               , 2) AS QualityScore
  FROM Metrics m
  LEFT JOIN Users u ON u.Id = m.OwnerUserId
  LEFT JOIN Posts p ON p.Id = m.PostId
)
SELECT *
FROM (
  SELECT
    PostId,
    OwnerUserId,
    OwnerDisplayName,
    Reputation,
    Location,
    Title,
    PostTypeId,
    Score,
    ViewCount,
    CommentCount,
    UpVotes,
    DownVotes,
    TagCount,
    Tags,
    LastActivityDate,
    LastEditorDisplayName,
    QualityScore
  FROM Enrich
  WHERE PostTypeId = 1 AND Score > 500
  UNION ALL
  SELECT
    PostId,
    OwnerUserId,
    OwnerDisplayName,
    Reputation,
    Location,
    Title,
    PostTypeId,
    Score,
    ViewCount,
    CommentCount,
    UpVotes,
    DownVotes,
    TagCount,
    Tags,
    LastActivityDate,
    LastEditorDisplayName,
    QualityScore
  FROM Enrich
  WHERE ViewCount > 1000
) AS combined
ORDER BY QualityScore DESC
LIMIT 100;