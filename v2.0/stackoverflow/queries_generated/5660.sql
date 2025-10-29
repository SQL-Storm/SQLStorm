-- {"query": "5660.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 799} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.ViewCount DESC,
        p.Score DESC,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
),
top_questions AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    rp.OwnerUserId,
    rp.Tags,
    rp.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation
  FROM ranked_posts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
  WHERE rp.PostTypeId = 1 AND rp.rn <= 100
),
recent_activity AS (
  SELECT
    pq.PostId,
    pq.Title,
    pq.CreationDate,
    pq.LastActivityDate,
    pq.OwnerUserId,
    pq.OwnerDisplayName,
    pq.Reputation,
    pq.ViewCount,
    pq.Score,
    pq.AnswerCount,
    -- simulate a correlated subquery: count of comments on recent posts by same user
    (
      SELECT COUNT(*)
      FROM Comments c
      WHERE c.PostId = pq.PostId
        AND c.CreationDate > pq.LastActivityDate - INTERVAL '30 days'
    ) AS RecentCommentCountByPost
  FROM top_questions pq
),
tag_cooccurrence AS (
  SELECT
    t1.TagName AS tag_a,
    t2.TagName AS tag_b,
    COUNT(*) AS pair_count
  FROM (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) t1
  CROSS JOIN (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) t2
  WHERE t1.TagName < t2.TagName
  GROUP BY t1.TagName, t2.TagName
  ORDER BY pair_count DESC
  LIMIT 50
),
windowed_stats AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.LastActivityDate,
    ra.Reputation,
    ra.OwnerDisplayName,
    ra.ViewCount,
    ra.Score,
    ra.AnswerCount,
    ra.RecentCommentCountByPost,
    -- running sum of views per owner
    SUM(ra.ViewCount) OVER (PARTITION BY ra.OwnerUserId ORDER BY ra.LastActivityDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS views_last_30d
  FROM recent_activity ra
)
SELECT
  ws.PostId,
  ws.Title,
  ws.LastActivityDate,
  ws.OwnerDisplayName,
  ws.Reputation,
  ws.ViewCount,
  ws.Score,
  ws.AnswerCount,
  ws.RecentCommentCountByPost,
  ws.views_last_30d,
  tc.tag_a,
  tc.tag_b,
  tc.pair_count
FROM windowed_stats ws
LEFT JOIN tag_cooccurrence tc ON 1=1
ORDER BY ws.LastActivityDate DESC
LIMIT 100;