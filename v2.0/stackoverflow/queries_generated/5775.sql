-- {"query": "5775.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 686} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '60 days'
),
tag_summary AS (
  SELECT
    unnest(string_to_array(trim(BOTH ' ' FROM p.Tags), '><')) AS tag,
    COUNT(*) AS questions_with_tag
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY tag
),
top_tags AS (
  SELECT
    tag,
    questions_with_tag
  FROM tag_summary
  ORDER BY questions_with_tag DESC
  LIMIT 5
),
recent_activity AS (
  SELECT
    p.Id AS post_id,
    p.Title,
    p.LastActivityDate,
    COALESCE(v.BountyAmount, 0) AS current_bounty,
    v1.Score AS upvotes,
    v2.Score AS downvotes
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
  LEFT JOIN Votes v1 ON p.Id = v1.PostId AND v1.VoteTypeId = 2
  LEFT JOIN Votes v2 ON p.Id = v2.PostId AND v2.VoteTypeId = 3
  LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) AS BountyAmount
    FROM Votes
    WHERE VoteTypeId = 8
    GROUP BY PostId
  ) v ON p.Id = v.PostId
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate >= NOW() - INTERVAL '14 days'
),
complex_filter AS (
  SELECT
    r.post_id,
    r.Title,
    r.LastActivityDate,
    r.current_bounty,
    r.upvotes,
    r.downvotes,
    CASE
      WHEN r.current_bounty > 0 THEN 'Has Bounty'
      WHEN r.upvotes - r.downvotes > 5 THEN 'Strong Positive'
      ELSE 'Normal'
    END AS activity_tag
  FROM recent_activity r
  ORDER BY r.LastActivityDate DESC
  LIMIT 100
)
SELECT
  q.PostId,
  q.Title,
  q.CreationDate,
  q.ViewCount,
  q.Score AS QuestionScore,
  q.OwnerDisplayName,
  q.OwnerReputation,
  ts.tag AS TopTag,
  ts.questions_with_tag,
  ca.activity_tag,
  ca.current_bounty,
  ca.upvotes,
  ca.downvotes,
  r.LastActivityDate AS LastActivity
FROM recent_questions q
LEFT JOIN top_tags ts
  ON 1 = 1
LEFT JOIN complex_filter ca
  ON ca.post_id = q.Id
ORDER BY q.LastActivityDate DESC
LIMIT 200;