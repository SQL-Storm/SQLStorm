-- {"query": "5176.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 824} 
WITH recent_failed_votes AS (
  SELECT
    v.PostId,
    v.UserId AS VoterId,
    v.CreationDate AS VoteDate,
    vt.Name AS VoteType,
    u.Reputation,
    u.DisplayName
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE vt.Name IN ('DownMod', 'Close', 'Spam') -- include interesting negative interactions
),
trend AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions only
),
complex_calc AS (
  SELECT
    t.PostId,
    t.Title,
    t.Tags,
    t.CreationDate,
    t.OwnerUserId,
    t.Score,
    t.ViewCount,
    t.LastActivityDate,
    t.UpVotes,
    t.DownVotes,
    t.CommentCount,
    t.rn_by_owner,
    CASE
      WHEN t.Score > 0 THEN t.Score * 1.0 / NULLIF(t.ViewCount,0)
      ELSE NULL
    END AS score_per_view,
    CASE
      WHEN t.LastActivityDate > now() - interval '30 days' THEN true
      ELSE false
    END AS ActiveRecently
  FROM trend t
),
aggregates AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.OwnerUserId,
    c.Score,
    c.ViewCount,
    c.LastActivityDate,
    c.UpVotes,
    c.DownVotes,
    c.CommentCount,
    c.rn_by_owner,
    c.score_per_view,
    c.ActiveRecently,
    u.Reputation,
    u.DisplayName,
    b.Class AS BadgeClass,
    b.Name AS BadgeName
  FROM complex_calc c
  LEFT JOIN Users u ON c.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE c.rn_by_owner <= 3 -- top 3 recent posts per owner
),
filtered AS (
  SELECT
    a.*,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = a.PostId AND pl.LinkTypeId = 1) AS LinkedCount,
    (SELECT ARRAY_AGG(p2.Id) FROM Posts p2 WHERE p2.ParentId = a.PostId) AS ChildPostIds
  FROM aggregates a
)
SELECT
  f.PostId,
  f.Title,
  f.Tags,
  f.CreationDate,
  f.OwnerUserId,
  f.DisplayName AS OwnerDisplayName,
  f.Reputation,
  f.ViewCount,
  f.LastActivityDate,
  f.Score,
  f.UpVotes,
  f.DownVotes,
  f.CommentCount,
  f.score_per_view,
  f.ActiveRecently,
  f.LinkedCount,
  f.ChildPostIds,
  f.BadgeName,
  f.BadgeClass,
  f.LinkedCount > 0 AS HasLinks
FROM filtered f
LEFT JOIN Posts p ON p.Id = f.PostId
LEFT JOIN Users u ON f.OwnerUserId = u.Id
ORDER BY f.LastActivityDate DESC, f.Score DESC
LIMIT 100;