-- {"query": "5991.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 579} 
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
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_popularity AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS total_score,
    COUNT(p.Id) AS question_count,
    AVG(p.ViewCount) AS avg_views
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(Tags, '><')) AS TagName
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
  (SELECT ARRAY_AGG(t.TagName) FROM string_to_array(cm.Title, ' ') AS st) AS title_tokens
FROM complex_metrics cm
JOIN LATERAL (
  SELECT unnest(string_to_array(cm.Title, ' ')) AS Token
) AS t ON TRUE
JOIN LATERAL (
  SELECT COUNT(*) AS token_hits
  FROM Unnest(string_to_array(cm.Title, ' ')) AS tkn
  WHERE tkn ILIKE '%benchmark%'
) AS b ON TRUE
WHERE cm.rn <= 100
ORDER BY cm.CreationDate DESC, cm.Score DESC;