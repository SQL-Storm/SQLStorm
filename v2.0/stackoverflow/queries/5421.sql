-- {"query": "5421.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 759}
WITH recent_comments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId,
    c.Score,
    c.Text,
    c.CreationDate,
    u.Reputation AS UserReputation,
    u.DisplayName AS UserDisplayName
  FROM
    Comments c
    LEFT JOIN Users u ON c.UserId = u.Id
  WHERE
    c.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
),
highly_active_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.CreationDate DESC) AS rn_by_owner
  FROM
    Posts p
  WHERE
    p.PostTypeId = 1
    AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
    AND p.ViewCount > 100
),
tag_expansion AS (
  SELECT
    ht.PostId,
    ht.Text AS RevisionText,
    ht.CreationDate AS RevisionDate,
    ht.UserDisplayName AS RevisionUser
  FROM
    PostHistory ht
  WHERE
    ht.PostHistoryTypeId = 5
    AND ht.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60' DAY
),
linked_pairs AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM
    PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE
    lt.Name IN ('Linked', 'Duplicate')
),
aggregates AS (
  SELECT
    ap.PostId,
    ap.Title,
    ap.OwnerUserId,
    ap.CreationDate,
    ap.ViewCount,
    ap.CommentCount,
    ap.AnswerCount,
    ap.Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ap.PostId) AS TotalComments,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.Id = ap.PostId) AS AvgPostScore,
    ap.LastActivityDate
  FROM
    highly_active_posts ap
  WHERE
    ap.rn_by_owner = 1
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerUserId,
  o.DisplayName AS OwnerDisplayName,
  a.CreationDate,
  a.ViewCount,
  a.CommentCount,
  a.AnswerCount,
  a.Tags,
  a.TotalComments,
  a.AvgPostScore,
  o.Reputation AS OwnerReputation,
  COALESCE(u2.DisplayName, ra.RevisionUser) AS LastEditorDisplayName,
  ra.RevisionDate,
  ra.RevisionText,
  rp.RelatedPostId,
  rp.LinkTypeName,
  c.Id AS CommentId,
  c.Text AS CommentText,
  c.CreationDate AS CommentDate,
  cu.DisplayName AS CommentUser,
  a.LastActivityDate
FROM
  aggregates a
  LEFT JOIN Users o ON a.OwnerUserId = o.Id
  LEFT JOIN Users u2 ON a.OwnerUserId = u2.Id
  LEFT JOIN tag_expansion ra ON a.PostId = ra.PostId
  LEFT JOIN linked_pairs rp ON a.PostId = rp.PostId
  LEFT JOIN Comments c ON c.PostId = a.PostId
  LEFT JOIN Users cu ON c.UserId = cu.Id
GROUP BY
  a.PostId,
  a.Title,
  a.OwnerUserId,
  o.DisplayName,
  a.CreationDate,
  a.ViewCount,
  a.CommentCount,
  a.AnswerCount,
  a.Tags,
  a.TotalComments,
  a.AvgPostScore,
  o.Reputation,
  u2.DisplayName,
  ra.RevisionUser,
  ra.RevisionDate,
  ra.RevisionText,
  rp.RelatedPostId,
  rp.LinkTypeName,
  c.Id,
  c.Text,
  c.CreationDate,
  cu.DisplayName,
  a.LastActivityDate
ORDER BY
  a.ViewCount DESC,
  a.LastActivityDate DESC
LIMIT 100;