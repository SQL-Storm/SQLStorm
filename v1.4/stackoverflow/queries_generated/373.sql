-- {"query": "373.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20621} 
WITH ScoreSet AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    pt.Name AS PostTypeName,
    p.CreationDate,
    p.OwnerUserId,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.Tags,
    p.Score AS MetricValue,
    'Score' AS MetricType,
    (p.AcceptedAnswerId IS NOT NULL) AS HasAcceptedAnswer,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0) AS NetVotes,
    CASE
      WHEN p.Tags IS NULL THEN 0
      ELSE COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1), 0)
    END AS TagCount,
    cl.CloseReasonName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS OwnerPostRank
  FROM Posts p
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
     SELECT SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
     FROM Votes V
     WHERE V.PostId = p.Id
  ) v ON true
  LEFT JOIN LATERAL (
     SELECT crt.Name AS CloseReasonName
     FROM PostHistory ph
     LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS int)
     WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^[0-9]+$'
     ORDER BY ph.CreationDate DESC
     LIMIT 1
  ) cl ON true
  WHERE p.CreationDate >= now() - interval '365 days'
    AND p.PostTypeId = 1
  ORDER BY p.Score DESC
  LIMIT 200
),
ViewSet AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    pt.Name AS PostTypeName,
    p.CreationDate,
    p.OwnerUserId,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    p.Tags,
    p.ViewCount AS MetricValue,
    'Views' AS MetricType,
    (p.AcceptedAnswerId IS NOT NULL) AS HasAcceptedAnswer,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(v.DownVotes, 0) AS DownVotes,
    COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0) AS NetVotes,
    CASE
      WHEN p.Tags IS NULL THEN 0
      ELSE COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), 1), 0)
    END AS TagCount,
    cl.CloseReasonName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS OwnerPostRank
  FROM Posts p
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
     SELECT SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
     FROM Votes V
     WHERE V.PostId = p.Id
  ) v ON true
  LEFT JOIN LATERAL (
     SELECT crt.Name AS CloseReasonName
     FROM PostHistory ph
     LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS int)
     WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 AND ph.Comment ~ '^[0-9]+$'
     ORDER BY ph.CreationDate DESC
     LIMIT 1
  ) cl ON true
  WHERE p.CreationDate >= now() - interval '30 days'
  ORDER BY p.ViewCount DESC
  LIMIT 200
)
SELECT *
FROM ScoreSet
UNION ALL
SELECT *
FROM ViewSet;