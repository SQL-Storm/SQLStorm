-- {"query": "5322.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 681} 
WITH
TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    -- Derived metrics per post
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= TIMESTAMP '2019-01-01 00:00:00'
),
Agg AS (
  SELECT
    p.PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    p.ParentId,
    -- Windowed aggregates
    SUM(CASE WHEN p.LastActivityDate > p.CreationDate + INTERVAL '7 days' THEN 1 ELSE 0 END) OVER (PARTITION BY p.PostTypeId) AS SevenDayActive,
    COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPerType
  FROM TopPosts p
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  a.CreationDate,
  a.ViewCount,
  a.Score,
  a.CommentCount,
  a.AnswerCount,
  a.Tags,
  a.LastActivityDate,
  a.PostTypeId,
  a.ParentId,
  a.SevenDayActive,
  a.TotalPerType,
  -- Complex predicate: posts with high engagement and recent activity, including NULL-safe checks
  CASE
    WHEN a.ViewCount IS NULL THEN 0
    ELSE a.ViewCount * 0.6 + COALESCE(a.Score,0) * 1.2 + COALESCE(a.CommentCount,0) * 0.8
  END AS EngagementMetric,
  -- String expression: lowercased title and tag normalization
  LOWER(REGEXP_REPLACE(a.Title, '[^A-Za-z0-9\s]', '', 'g')) AS NormalizedTitle,
  -- Correlated subquery: count of related posts via PostLinks where this post links to others
  (
    SELECT COUNT(*) 
    FROM PostLinks pl
    WHERE pl.PostId = a.PostId
  ) AS LinkedCount,
  -- Correlated subquery with NULL handling: count of comments on this post with non-null user
  (
    SELECT COUNT(*) 
    FROM Comments c
    WHERE c.PostId = a.PostId AND c.UserId IS NOT NULL
  ) AS CommenterCount
FROM Agg a
LEFT JOIN Users u ON a.OwnerUserId = u.Id
ORDER BY a.SevenDayActive DESC, a.Score DESC, a.ViewCount DESC
LIMIT 100;