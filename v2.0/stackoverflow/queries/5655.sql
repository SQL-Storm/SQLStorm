-- {"query": "5655.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 778}
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
AggregatedActivity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    COALESCE(pv.UpVotes, 0) AS UpVotes,
    COALESCE(pv.DownVotes, 0) AS DownVotes,
    CAST(p.Body AS TEXT) AS BodySnippet,
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount
  FROM RecentTopPosts rp
  LEFT JOIN Posts p ON rp.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) pv ON pv.PostId = p.Id
  WHERE rp.rn = 1
  GROUP BY rp.PostId, rp.Title, rp.OwnerName, rp.CreationDate, rp.Score, rp.ViewCount, rp.Tags, p.Body, pv.UpVotes, pv.DownVotes
),
TopLinks AS (
  SELECT
    a.PostId,
    COUNT(*) AS LinkedCount
  FROM PostLinks a
  JOIN PostLinks b ON a.RelatedPostId = b.PostId
  WHERE a.LinkTypeId = 1
  GROUP BY a.PostId
),
Hotness AS (
  SELECT
    aa.PostId,
    aa.Title,
    aa.OwnerName,
    aa.CreationDate,
    aa.Score,
    aa.ViewCount,
    aa.Tags,
    aa.UpVotes,
    aa.DownVotes,
    aa.BodySnippet,
    ca.CommentCount,
    hl.LinkedCount,
    (aa.Score * 2 + aa.ViewCount / 10 + ca.CommentCount * 3 + COALESCE(hl.LinkedCount, 0) * 5) AS HotScore
  FROM AggregatedActivity aa
  LEFT JOIN TopLinks tl ON aa.PostId = tl.PostId
  LEFT JOIN (
    SELECT
      p.Id AS Id,
      COUNT(*) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id
  ) ca ON aa.PostId = ca.Id
  LEFT JOIN TopLinks hl ON aa.PostId = hl.PostId
)
SELECT
  PostId,
  Title,
  OwnerName,
  CreationDate,
  Score,
  ViewCount,
  Tags,
  UpVotes,
  DownVotes,
  BodySnippet,
  CommentCount,
  LinkedCount,
  HotScore
FROM Hotness
ORDER BY HotScore DESC
LIMIT 50;