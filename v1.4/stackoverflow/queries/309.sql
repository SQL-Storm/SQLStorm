-- {"query": "309.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20677} 
WITH
  Q AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.LastActivityDate,
      p.AcceptedAnswerId,
      p.ParentId,
      p.Body,
      p.LastEditDate,
      p.LastEditorUserId,
      p.LastEditorDisplayName,
      CASE
        WHEN p.Tags IS NULL THEN 0
        ELSE COALESCE(array_length(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags) - 2, 0)), '><'), 1), 0)
      END AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
      AND (p.Score > 0 OR p.ViewCount > 100)
  ),
  T AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.LastActivityDate,
      p.AcceptedAnswerId,
      p.ParentId,
      p.Body,
      p.LastEditDate,
      p.LastEditorUserId,
      p.LastEditorDisplayName,
      CASE
        WHEN p.Tags IS NULL THEN 0
        ELSE COALESCE(array_length(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags) - 2, 0)), '><'), 1), 0)
      END AS TagCount
    FROM Posts p
    WHERE p.PostTypeId IN (4, 5)
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
  ),
  AllPosts AS (
    SELECT
      q.Id, q.PostTypeId, q.OwnerUserId, q.Title, q.Tags, q.CreationDate, q.Score, q.ViewCount, q.LastActivityDate, q.AcceptedAnswerId, q.ParentId, q.Body, q.LastEditDate, q.LastEditorUserId, q.LastEditorDisplayName, q.TagCount
    FROM Q q
    UNION ALL
    SELECT
      t.Id, t.PostTypeId, t.OwnerUserId, t.Title, t.Tags, t.CreationDate, t.Score, t.ViewCount, t.LastActivityDate, t.AcceptedAnswerId, t.ParentId, t.Body, t.LastEditDate, t.LastEditorUserId, t.LastEditorDisplayName, t.TagCount
    FROM T t
  ),
  VoteAgg AS (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ),
  CommentAgg AS (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ),
  Enriched AS (
    SELECT
      ap.Id,
      ap.PostTypeId,
      ap.OwnerUserId,
      COALESCE(u.DisplayName, 'Community') AS OwnerDisplayName,
      ap.Title,
      ap.Tags,
      ap.CreationDate,
      ap.Score,
      ap.ViewCount,
      ap.LastActivityDate,
      ap.AcceptedAnswerId,
      ap.ParentId,
      ap.Body,
      ap.LastEditDate,
      ap.LastEditorUserId,
      ap.LastEditorDisplayName,
      ap.TagCount,
      COALESCE(v.UpVotes, 0) AS UpVotes,
      COALESCE(v.DownVotes, 0) AS DownVotes,
      COALESCE(c.CommentCount, 0) AS CommentCount,
      COALESCE(u.Reputation, 0) AS OwnerReputation,
      ROW_NUMBER() OVER (PARTITION BY ap.PostTypeId ORDER BY ap.Score DESC, ap.LastActivityDate DESC) AS rn,
      (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ap.OwnerUserId AND p2.PostTypeId = ap.PostTypeId AND p2.Id <> ap.Id) AS SimilarPostCount
    FROM AllPosts ap
    LEFT JOIN VoteAgg v ON v.PostId = ap.Id
    LEFT JOIN CommentAgg c ON c.PostId = ap.Id
    LEFT JOIN Users u ON u.Id = ap.OwnerUserId
  )
SELECT
  Id,
  PostTypeId,
  OwnerUserId,
  OwnerDisplayName,
  Title,
  Tags,
  CreationDate,
  Score,
  ViewCount,
  LastActivityDate,
  AcceptedAnswerId,
  ParentId,
  Body,
  UpVotes,
  DownVotes,
  CommentCount,
  LastEditDate,
  LastEditorUserId,
  LastEditorDisplayName,
  TagCount,
  OwnerReputation,
  SimilarPostCount,
  rn,
  (Title || ' by ' || OwnerDisplayName) AS PostSummary
FROM Enriched
WHERE rn <= 200
ORDER BY PostTypeId, Score DESC, LastActivityDate DESC
LIMIT 200;