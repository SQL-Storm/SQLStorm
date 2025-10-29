-- {"query": "5424.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 936}
WITH recent_top_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
top_posts_with_owner AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.Tags,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    r.LastActivityDate,
    r.PostTypeId,
    (r.LastActivityDate - r.CreationDate) AS AgeDays
  FROM recent_top_posts r
  LEFT JOIN Users u ON r.OwnerUserId = u.Id
  WHERE r.rn <= 5
),
complex_filters AS (
  SELECT
    tpw.PostId,
    tpw.Title,
    tpw.CreationDate,
    tpw.Score,
    tpw.ViewCount,
    tpw.Tags,
    tpw.OwnerDisplayName,
    tpw.Reputation,
    tpw.LastActivityDate,
    tpw.PostTypeId,
    CASE
      WHEN tpw.PostTypeId = 1 THEN 'Question'
      WHEN tpw.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - tpw.CreationDate)) / 86400 AS AgeDays
  FROM top_posts_with_owner tpw
),
tag_metrics AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerDisplayName,
    c.Reputation,
    c.PostKind,
    c.AgeDays,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesSeen,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesSeen,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
  FROM complex_filters c
  LEFT JOIN Votes v ON v.PostId = c.PostId
  GROUP BY c.PostId, c.Title, c.OwnerDisplayName, c.Reputation, c.PostKind, c.AgeDays
),
linked_mentions AS (
  SELECT
    tm.PostId,
    tm.Title,
    tm.OwnerDisplayName,
    tm.Reputation,
    tm.PostKind,
    tm.AgeDays,
    COALESCE(MAX(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END), 0) = 1 AS HasLinked,
    COALESCE(MAX(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END), 0) = 1 AS IsDuplicate,
    tm.TotalUpvotes,
    tm.TotalDownvotes
  FROM tag_metrics tm
  LEFT JOIN PostLinks pl ON pl.PostId = tm.PostId
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY tm.PostId, tm.Title, tm.OwnerDisplayName, tm.Reputation, tm.PostKind, tm.AgeDays, tm.TotalUpvotes, tm.TotalDownvotes
)
SELECT
  plm.PostId,
  plm.Title,
  plm.OwnerDisplayName,
  plm.Reputation,
  plm.PostKind,
  plm.AgeDays,
  plm.TotalUpvotes,
  plm.TotalDownvotes,
  plm.HasLinked,
  plm.IsDuplicate,
  (plm.TotalUpvotes - plm.TotalDownvotes) AS NetScore,
  (CASE
     WHEN plm.AgeDays < 7 THEN 'New'
     WHEN plm.AgeDays < 30 THEN 'Rising'
     ELSE 'Stale'
   END) AS LifecycleCategory,
  (SELECT COUNT(*) FROM Comments c2 WHERE c2.PostId = plm.PostId) AS CommentCount
FROM linked_mentions plm
ORDER BY plm.AgeDays DESC, plm.TotalUpvotes DESC
LIMIT 100;