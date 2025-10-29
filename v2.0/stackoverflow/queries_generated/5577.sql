-- {"query": "5577.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 977} 
WITH
-- recent activity by user with heavy interactions
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
),
-- determine correlation of user reputation to activity using window functions
TopUsers AS (
  SELECT
    a.UserId,
    a.DisplayName,
    a.PostCount,
    a.TotalViews,
    a.Upvotes,
    a.Downvotes,
    a.LastActive,
    ROW_NUMBER() OVER (
      PARTITION BY CASE WHEN a.TotalViews > 1000 THEN 1 ELSE 0 END
      ORDER BY a.TotalViews DESC, a.Upvotes - a.Downvotes DESC, a.LastActive DESC
    ) AS rn
  FROM UserActivity a
),
-- compile a complex set of post-level metrics with correlated subqueries
PostMetrics AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id) AS ChildCount,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id) AS AvgBounty,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
-- rich materialized result combining multiple constructs
BenchmarkData AS (
  SELECT
    pm.PostId,
    pm.Title,
    pm.PostTypeId,
    pm.Score,
    pm.ViewCount,
    pm.CommentCount,
    pm.ParentId,
    pm.OwnerUserId,
    pm.CreationDate,
    pm.LastActivityDate,
    pm.LinkCount,
    CASE
      WHEN pm.PostTypeId = 1 THEN 'Question'
      WHEN pm.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    -- compute a complex derived metric with NULL handling
    COALESCE((pm.Score * 1.15) / NULLIF(pm.ViewCount, 0), 0) AS EngagementIndex,
    -- tag-based string expression
    (SELECT STRING_AGG(t.TagName, ',')
     FROM Tags t
     JOIN Posts pt ON pt.Id = pm.PostId
     WHERE t.Id = pt.Id OR t.Id IN (SELECT TagName FROM UNNEST(string_to_array(pt.Tags, '>') ) AS TagName)
    ) AS TagList
  FROM PostMetrics pm
),
-- final outer join enriched with top users and recent activity
Final AS (
  SELECT
    b.PostId,
    b.Title,
    b.PostTypeId,
    b.PostKind,
    b.Score,
    b.ViewCount,
    b.CommentCount,
    b.ParentId,
    b.OwnerUserId,
    b.CreationDate,
    b.LastActivityDate,
    b.LinkCount,
    b.EngagementIndex,
    b.TagList,
    ta.DisplayName AS OwnerDisplayName,
    ta.Reputation
  FROM BenchmarkData b
  LEFT JOIN Users ta ON ta.Id = b.OwnerUserId
  LEFT JOIN TopUsers tu ON tu.UserId = b.OwnerUserId
  WHERE b.EngagementIndex > 0
  ORDER BY b.EngagementIndex DESC, b.ViewCount DESC
  LIMIT 500
)
SELECT
  f.PostId,
  f.Title,
  f.PostKind,
  f.Score,
  f.ViewCount,
  f.CommentCount,
  f.TagList,
  f.EngagementIndex,
  f.OwnerDisplayName,
  f.Reputation,
  f.LastActivityDate
FROM Final f
WHERE f.PostTypeId IN (1,2)
  AND f.TagList IS NOT NULL
  AND (f.EngagementIndex > (SELECT AVG(EngagementIndex) FROM Final))
ORDER BY f.EngagementIndex DESC, f.ViewCount DESC;