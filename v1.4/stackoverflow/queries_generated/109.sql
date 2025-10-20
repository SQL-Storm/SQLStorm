-- {"query": "109.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2029} 
WITH
recent_questions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
net_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) -
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes
  FROM Votes v
  GROUP BY v.PostId
),
link_counts AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkEdges
  FROM PostLinks pl
  GROUP BY pl.PostId
),
owner_reputation AS (
  SELECT
    u.Id,
    u.Reputation,
    u.DisplayName,
    u.LastAccessDate,
    u.AccountId,
    u.Location,
    u.WorldReadable
  FROM Users u
),
tag_summary AS (
  SELECT
    t.Id AS TagPostId,
    t.TagName,
    t.Count AS TagCount,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
composite AS (
  SELECT
    rq.Id AS PostId,
    rq.Title,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.ViewCount,
    rq.AnswerCount,
    rq.CommentCount,
    COALESCE(nv.NetVotes, 0) AS NetVotes,
    COALESCE(lc.LinkEdges, 0) AS LinkEdges,
    orp.Reputation,
    orp.DisplayName AS OwnerDisplayName,
    rq.Tags
  FROM recent_questions rq
  LEFT JOIN net_votes nv ON nv.PostId = rq.Id
  LEFT JOIN link_counts lc ON lc.PostId = rq.Id
  LEFT JOIN owner_reputation orp ON orp.Id = rq.OwnerUserId
),
ranked AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (
      PARTITION BY CASE WHEN c.NetVotes >= 0 THEN 1 ELSE 0 END
      ORDER BY c.NetVotes DESC, c.ViewCount DESC, c.CreationDate DESC
    ) AS rn
  FROM composite c
),
selected AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.LastActivityDate,
    r.ViewCount,
    r.AnswerCount,
    r.CommentCount,
    r.NetVotes,
    r.LinkEdges,
    r.Reputation,
    r.OwnerDisplayName,
    r.Tags,
    r.rn
  FROM ranked r
  WHERE r.rn <= 100
),
union_part AS (
  -- A second benchmarking subset: posts with zero net votes but high activity
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    0 AS NetVotes,
    COALESCE(lc.LinkEdges, 0) AS LinkEdges,
    COALESCE(orp.Reputation, 0) AS Reputation,
    p.OwnerDisplayName,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN link_counts lc ON lc.PostId = p.Id
  LEFT JOIN owner_reputation orp ON orp.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1
    AND COALESCE(lc.LinkEdges, 0) = 0
    AND p.LastActivityDate >= NOW() - INTERVAL '90 days'
)
SELECT
  PostId,
  Title,
  CreationDate,
  LastActivityDate,
  ViewCount,
  AnswerCount,
  CommentCount,
  NetVotes,
  LinkEdges,
  Reputation,
  OwnerDisplayName,
  Tags
FROM selected
UNION ALL
SELECT
  PostId,
  Title,
  CreationDate,
  LastActivityDate,
  ViewCount,
  NULL AS AnswerCount,
  NULL AS CommentCount,
  NetVotes,
  LinkEdges,
  Reputation,
  OwnerDisplayName,
  Tags
FROM union_part
ORDER BY NetVotes DESC NULLS LAST, ViewCount DESC NULLS LAST
LIMIT 300;