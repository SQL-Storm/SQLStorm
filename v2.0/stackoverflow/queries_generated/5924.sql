-- {"query": "5924.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 648} 
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
    p.CommentCount,
    p.AnswerCount,
    ut.Reputation AS UserReputation,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT Id, Reputation, DisplayName
    FROM Users
  ) ut ON ut.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
popular_tags AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    COUNT(*) AS tag_count
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY 1
),
tag_metrics AS (
  SELECT
    t.tag,
    t.tag_count,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags LIKE '%' || t.tag || '%') AS avg_question_score,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId IN (1,2) AND p.Tags LIKE '%' || t.tag || '%') AS related_posts
  FROM popular_tags t
  GROUP BY t.tag, t.tag_count
),
activity AS (
  SELECT
    p.OwnerUserId,
    MAX(p.LastActivityDate) AS last_activity
  FROM Posts p
  GROUP BY p.OwnerUserId
),
combined AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.OwnerName,
    q.UserReputation,
    q.LastActivityDate,
    q.CommentCount,
    q.AnswerCount,
    a.last_activity,
    m.tag_metrics
  FROM recent_questions q
  LEFT JOIN activity a ON q.OwnerUserId = a.OwnerUserId
  LEFT JOIN tag_metrics m ON EXISTS (
      SELECT 1
      FROM unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS t(tag)
      WHERE m.tag = t.tag
  )
  WHERE q.rn = 1
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.OwnerName,
  c.UserReputation,
  c.LastActivityDate,
  c.CommentCount,
  c.AnswerCount,
  c.last_activity,
  c.tag_metrics
FROM combined c
ORDER BY c.LastActivityDate DESC
LIMIT 100;