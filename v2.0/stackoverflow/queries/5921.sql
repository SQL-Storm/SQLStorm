-- {"query": "5921.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 627}
WITH recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    u.Reputation,
    u.DisplayName,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate AS PostCreationDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
             WHEN v.VoteTypeId = 3 THEN -1
             ELSE 0 END) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS net_votes_up_down
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  LEFT JOIN Users u ON u.Id = v.UserId
  WHERE v.VoteTypeId IN (2,3)
),
qualified_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate AS PostCreationDate,
    rd.net_votes_up_down,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = p.Id AND vv.VoteTypeId = 2) AS UpVotes
  FROM Posts p
  LEFT JOIN recent_votes rd ON rd.PostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1
    AND p.ViewCount > 100
    AND p.Score > 0
    AND p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days')
),
tag_exploded AS (
  SELECT
    qp.*,
    CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - qp.PostCreationDate)) / 86400 AS INTEGER) AS age_days,
    (unnest(string_to_array(substring(qp.Tags, 2, length(qp.Tags)-2), '><'))) AS TagName
  FROM qualified_posts qp
),
segmented AS (
  SELECT
    te.PostId,
    te.Title,
    te.Tags,
    te.OwnerUserId,
    te.Score,
    te.ViewCount,
    te.PostCreationDate,
    te.net_votes_up_down,
    te.OwnerReputation,
    te.OwnerDisplayName,
    te.CommentCount,
    te.UpVotes,
    te.age_days,
    COALESCE(STRING_AGG(te.TagName, ',' ORDER BY te.TagName), '') AS tagstring
  FROM tag_exploded te
  GROUP BY
    te.PostId,
    te.Title,
    te.Tags,
    te.OwnerUserId,
    te.Score,
    te.ViewCount,
    te.PostCreationDate,
    te.net_votes_up_down,
    te.OwnerReputation,
    te.OwnerDisplayName,
    te.CommentCount,
    te.UpVotes,
    te.age_days
)
SELECT
  s.PostId,
  s.Title,
  s.OwnerDisplayName,
  s.OwnerReputation,
  s.ViewCount,
  s.Score,
  s.CommentCount,
  s.UpVotes,
  s.net_votes_up_down,
  s.age_days,
  s.tagstring
FROM segmented s
ORDER BY s.net_votes_up_down DESC, s.ViewCount DESC
LIMIT 100;