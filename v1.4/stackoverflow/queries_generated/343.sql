-- {"query": "343.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 25707} 
WITH q AS (
  SELECT
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    p.Title,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    p.OwnerUserId AS OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.LastEditorDisplayName,
    COALESCE(tt.TagTop3, '') AS TagTop3,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COALESCE(SUM(CASE WHEN v2.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) FROM Votes v2 WHERE v2.PostId = p.Id) AS UpVotes,
    (SELECT COALESCE(SUM(CASE WHEN v3.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) FROM Votes v3 WHERE v3.PostId = p.Id) AS DownVotes,
    CASE WHEN p.AcceptedAnswerId IS NULL THEN 'No' ELSE 'Yes' END AS HasAccepted,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS TypeRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN LATERAL (
     SELECT string_agg(tag, ',') AS TagTop3
     FROM (
        SELECT tag
        FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
        ORDER BY tag
        LIMIT 3
     ) s
  ) tt ON TRUE
  WHERE p.PostTypeId = 1
),
a AS (
  SELECT
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    p.Title,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    p.OwnerUserId AS OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.LastEditorDisplayName,
    COALESCE(tt.TagTop3, '') AS TagTop3,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COALESCE(SUM(CASE WHEN v2.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) FROM Votes v2 WHERE v2.PostId = p.Id) AS UpVotes,
    (SELECT COALESCE(SUM(CASE WHEN v3.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) FROM Votes v3 WHERE v3.PostId = p.Id) AS DownVotes,
    CASE WHEN p.AcceptedAnswerId IS NULL THEN 'No' ELSE 'Yes' END AS HasAccepted,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS TypeRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN LATERAL (
     SELECT string_agg(tag, ',') AS TagTop3
     FROM (
        SELECT tag
        FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
        ORDER BY tag
        LIMIT 3
     ) s
  ) tt ON TRUE
  WHERE p.PostTypeId = 2
)
SELECT *
FROM (
  SELECT * FROM q
  UNION ALL
  SELECT * FROM a
) s
WHERE s.TypeRank <= 50
ORDER BY s.PostTypeName, s.TypeRank;