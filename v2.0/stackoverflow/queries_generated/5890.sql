-- {"query": "5890.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 757} 
WITH
recent_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_count
  FROM
    Posts p
    JOIN Tags tg ON tg.Id = p.Tags -- assuming Tags association as in schema
  WHERE
    p.CreationDate >= NOW() - INTERVAL '30 days'
  GROUP BY
    t.TagName
),
top_users AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rn
  FROM
    Users u
  WHERE
    u.Reputation > 1000
),
complex_post_stats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    COALESCE(a.Score, 0) AS AcceptedScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id) AS VoteCount,
    -- window function to rank recent edits per post
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.LastEditDate DESC NULLS LAST) AS EditRank
  FROM
    Posts p
    LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
  WHERE
    p.PostTypeId IN (1, 2) -- Questions and Answers
),
extensive_predicate AS (
  SELECT
    c.PostId,
    c.Comment,
    c.CreationDate,
    c.UserId,
    c.Text,
    CASE
      WHEN c.UserId IS NULL THEN 'anon'
      WHEN u.Reputation IS NULL THEN 'unknown'
      ELSE 'user'
    END AS UserCategory
  FROM
    Comments c
    LEFT JOIN Users u ON c.UserId = u.Id
  WHERE
    c.CreationDate >= NOW() - INTERVAL '7 days'
    AND (c.Text LIKE '%performance%' OR c.Text LIKE '%benchmark%')
),
final AS (
  SELECT
    cp.PostId,
    cp.Title,
    cp.PostTypeId,
    cu.DisplayName AS OwnerName,
    cu.Reputation AS OwnerRep,
    cp.CreationDate,
    cp.LastActivityDate,
    cp.Score,
    CASE
      WHEN pv.BountyAmount IS NULL THEN 0
      ELSE pv.BountyAmount
    END AS CurrentBounty,
    tc.tag_count,
    tu.rn AS TopUserRank,
    ep.EditRank
  FROM
    complex_post_stats cp
    LEFT JOIN Users cu ON cp.OwnerUserId = cu.Id
    LEFT JOIN (
      SELECT p.Id, MAX(v.BountyAmount) AS BountyAmount
      FROM Posts p
      LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
      GROUP BY p.Id
    ) pv ON cp.PostId = pv.Id
    LEFT JOIN recent_tags rt ON 1=1
    LEFT JOIN top_users tu ON tu.rn <= 100
    LEFT JOIN (
      SELECT PostId, MAX(EditRank) AS EditRank
      FROM extensive_predicate
      GROUP BY PostId
    ) ep ON cp.PostId = ep.PostId
)
SELECT
  *
FROM
  final
WHERE
  OwnerRep IS NOT NULL
  AND CurrentBounty >= 0
ORDER BY
  OwnerRep DESC,
  LastActivityDate DESC
LIMIT 100;