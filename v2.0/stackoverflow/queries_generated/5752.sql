-- {"query": "5752.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 781} 
WITH
recent_qs AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
tag_cooccurrence AS (
  SELECT
    t1.TagName AS TagA,
    t2.TagName AS TagB,
    COUNT(*) AS Cooccurrence
  FROM Tags tg1
  JOIN Posts p1 ON p1.Id = tg1.Id
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p1.Tags, 2, length(p1.Tags)-2), '><')) AS TagName
  ) t1
  JOIN Tags tg2 ON tg2.Id = tg1.Id
  JOIN Posts p2 ON p2.Id = tg2.Id
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p2.Tags, 2, length(p2.Tags)-2), '><')) AS TagName
  ) t2
  WHERE p1.Id <> p2.Id
  GROUP BY t1.TagName, t2.TagName
  HAVING COUNT(*) > 0
),
most_viewed AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerDisplayName,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags
  FROM recent_qs p
  ORDER BY p.ViewCount DESC
  LIMIT 50
),
complex_metrics AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.LastActivityDate,
    v_sum.TotalUp AS UpVotes,
    v_sum.TotalDown AS DownVotes,
    (v_sum.TotalUp - v_sum.TotalDown) AS NetVotes,
    CASE
      WHEN q.OwnerUserId IS NULL THEN 'Anonymous'
      WHEN u.Reputation IS NULL THEN 'Unknown'
      ELSE u.Reputation::text
    END AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName
  FROM recent_qs q
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS TotalUp,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY PostId
  ) v_sum ON v_sum.PostId = q.Id
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  ORDER BY q.CreationDate DESC
  LIMIT 200
)
SELECT
  cm.PostId,
  cm.Title,
  cm.OwnerDisplayName,
  cm.CreationDate,
  cm.ViewCount,
  cm.Score,
  cm.AnswerCount,
  cm.CommentCount,
  cm.LastActivityDate,
  cm.UpVotes,
  cm.DownVotes,
  cm.NetVotes,
  cm.OwnerReputation
FROM complex_metrics cm
LEFT JOIN most_viewed mv ON mv.Id = cm.PostId
LEFT JOIN tag_cooccurrence tc ON tc.TagA = ANY(string_to_array(substr(cm.Title, 2, length(cm.Title)-2), '><'))
ORDER BY cm.CreationDate DESC
LIMIT 100;