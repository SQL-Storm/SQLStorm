WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
tag_popularity AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS total_score,
    COUNT(p.Id) AS question_count,
    AVG(p.ViewCount) AS avg_views
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(p.Tags, '><')) AS TagName
  ) AS t ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
complex_metrics AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerDisplayName,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.rn,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.PostId) AS answer_count,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS comment_count,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = q.PostId AND v.VoteTypeId = 8) AS avg_bounty,
    (SELECT STRING_AGG(vt.Name, ',') FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id WHERE v.PostId = q.PostId AND v.VoteTypeId IN (2,3)) AS recent_votes
  FROM recent_questions q
)
SELECT
  cm.PostId,
  cm.Title,
  cm.OwnerDisplayName,
  cm.CreationDate,
  cm.Score,
  cm.ViewCount,
  cm.answer_count,
  cm.comment_count,
  cm.avg_bounty,
  cm.recent_votes,
  (SELECT ARRAY_AGG(token) FROM (SELECT unnest(string_to_array(cm.Title, ' ')) AS token) AS tokens) AS title_tokens,
  t.Token,
  b.token_hits
FROM complex_metrics cm
JOIN LATERAL (
  SELECT unnest(string_to_array(cm.Title, ' ')) AS Token
) AS t ON TRUE
JOIN LATERAL (
  SELECT COUNT(*) AS token_hits
  FROM (SELECT unnest(string_to_array(cm.Title, ' ')) AS tkn) AS toks
  WHERE toks.tkn ILIKE '%benchmark%'
) AS b ON TRUE
WHERE cm.rn <= 100
GROUP BY
  cm.PostId,
  cm.Title,
  cm.OwnerDisplayName,
  cm.CreationDate,
  cm.Score,
  cm.ViewCount,
  cm.answer_count,
  cm.comment_count,
  cm.avg_bounty,
  cm.recent_votes,
  t.Token,
  b.token_hits
ORDER BY cm.CreationDate DESC, cm.Score DESC;