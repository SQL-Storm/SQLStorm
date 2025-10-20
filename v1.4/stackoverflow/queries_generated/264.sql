-- {"query": "264.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 9804} 
WITH
Q AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
    COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1), 0) AS TagCount,
    (p.Score * LN(1.0 + COALESCE(p.ViewCount,0))) AS Weight,
    p.OwnerUserId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
A AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
    COALESCE(array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1), 0) AS TagCount,
    (p.Score * LN(1.0 + COALESCE(p.ViewCount,0))) AS Weight,
    p.OwnerUserId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 2
)
SELECT
  t.PostId,
  t.Title,
  t.OwnerName,
  t.Score,
  t.ViewCount,
  t.CommentCount,
  t.UpVotes,
  t.DownVotes,
  t.LinkCount,
  t.TagCount,
  t.Weight,
  ROW_NUMBER() OVER (ORDER BY t.Weight DESC) AS rn,
  (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = t.OwnerUserId) AS OwnerScoreAvgCorrelated
FROM (
  SELECT * FROM Q
  UNION ALL
  SELECT * FROM A
) AS t
ORDER BY t.Weight DESC
LIMIT 200;