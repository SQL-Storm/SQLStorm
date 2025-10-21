-- {"query": "58.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 675} 
WITH recent_top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner,
    COUNT(*) OVER () AS total_rows
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
annotated AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.OwnerName,
    r.LastActivityDate,
    r.rn_owner,
    -- correlated subquery: number of comments on the post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId) AS CommentCount,
    -- correlated subquery: number of votes of type UpMod (2)
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 2) AS UpVotesForPost,
    -- compute a complex expression: engagement score with NULL-safe handling
    (COALESCE(r.Score,0) * 1.5 + COALESCE(r.ViewCount,0) * 0.5 +
     (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.PostId) * 2) AS EngagementScore
  FROM recent_top_questions r
),
windowed AS (
  SELECT
    PostId,
    Title,
    Tags,
    CreationDate,
    Score,
    ViewCount,
    OwnerUserId,
    OwnerName,
    LastActivityDate,
    CommentCount,
    UpVotesForPost,
    EngagementScore,
    ROW_NUMBER() OVER (ORDER BY EngagementScore DESC, LastActivityDate DESC NULLS LAST) AS rk,
    COUNT(*) OVER () AS total
  FROM annotated a
)
SELECT
  wk.PostId,
  wk.Title,
  wk.Tags,
  wk.CreationDate,
  wk.Score,
  wk.ViewCount,
  wk.OwnerUserId,
  wk.OwnerName,
  wk.LastActivityDate,
  wk.CommentCount,
  wk.UpVotesForPost,
  wk.EngagementScore,
  wk.rk,
  wk.total
FROM windowed wk
LEFT JOIN Posts p ON wk.PostId = p.Id
LEFT JOIN PostHistory ph ON ph.PostId = wk.PostId
WHERE wk.rk <= 100
  AND (p.ClosedDate IS NULL OR p.ClosedDate > cast('2024-10-01 12:34:56' as timestamp))
  AND NOT EXISTS (
    SELECT 1
    FROM Votes v2
    WHERE v2.PostId = wk.PostId
      AND v2.VoteTypeId = 4 -- Offensive votes
      AND v2.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
  )
ORDER BY wk.EngagementScore DESC, wk.LastActivityDate DESC NULLS LAST;