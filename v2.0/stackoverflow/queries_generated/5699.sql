-- {"query": "5699.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 961} 
WITH
-- 1) aggregate activity per user: posts created, recent edits, comments, votes
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.OwnerUserId = u.Id) AS PostsCreated,
    COUNT(DISTINCT ph.Id) AS PostHistoryEdits,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT v.Id) AS VotesCast,
    MAX(p.CreationDate) AS LastPostDate,
    MAX(ph.CreationDate) AS LastEditDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
-- 2) compute a complex derived metric: weighted score using NULL-safe expressions
UserMetrics AS (
  SELECT
    ua.UserId,
    ua.UserName,
    -- score combines posts, edits, comments, and votes with non-linear weights
    COALESCE(PostsCreated,0) * 3.5
    + COALESCE(PostHistoryEdits,0) * 1.8
    + COALESCE(CommentsMade,0) * 0.9
    + COALESCE(VotesCast,0) * 2.1
    + CASE
        WHEN LastPostDate IS NULL THEN 0
        ELSE EXTRACT(EPOCH FROM (NOW() - LastPostDate)) / 86400
      END * -0.5
    + CASE
        WHEN LastEditDate IS NULL THEN 0
        ELSE EXTRACT(EPOCH FROM (NOW() - LastEditDate)) / 86400
      END * 0.2 AS ActivityScore
  FROM UserActivity ua
),
-- 3) identify top engaging posts per user via window function
TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY
        (CASE WHEN p.PostTypeId = 1 THEN p.Score * 1.5 ELSE p.Score * 0.8 END)
        + p.ViewCount * 0.01
        + EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 86400 * -0.3
    ) AS rn
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
-- 4) perform an advanced join with tag data and tag-related links
TagAnalytics AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count AS TagCount,
    wa.PostId AS LinkedPostWithTag,
    pl.LinkTypeId
  FROM Tags t
  LEFT JOIN LATERAL (
    SELECT p.Id AS PostId
    FROM Posts p
    WHERE p.Tags LIKE '%' || t.TagName || '%' 
    ORDER BY p.CreationDate DESC
    LIMIT 1
  ) wa ON true
  LEFT JOIN PostLinks pl ON pl.PostId = wa.PostId
  WHERE t.IsModeratorOnly = 0 OR t.IsModeratorOnly IS NULL
),
-- 5) final selective filter with complex predicates to benchmark NULL handling and predicates
FinalPick AS (
  SELECT
    me.UserId,
    me.UserName,
    me.ActivityScore,
    tp.PostId AS TopPostId,
    tp.Title AS TopPostTitle,
    tp.PostTypeId AS TopPostType,
    ta.TagName
  FROM UserMetrics me
  LEFT JOIN (
    SELECT * FROM TopPosts WHERE rn = 1
  ) tp ON tp.OwnerUserId = me.UserId
  LEFT JOIN TagAnalytics ta ON ta.LinkedPostWithTag = tp.PostId
  ORDER BY me.ActivityScore DESC
  LIMIT 100
)
SELECT
  fp.UserId,
  fp.UserName,
  fp.ActivityScore,
  fp.TopPostId,
  fp.TopPostTitle,
  CASE fp.TopPostType
    WHEN 1 THEN 'Question'
    WHEN 2 THEN 'Answer'
    ELSE 'Other'
  END AS TopPostKind,
  fp.TagName
FROM FinalPick fp
ORDER BY fp.ActivityScore DESC, fp.UserName ASC;