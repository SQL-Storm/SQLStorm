-- {"query": "5806.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 752} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.Body,
    p.LastActivityDate,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpModCount
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
  GROUP BY p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId, p.Tags, p.Body, p.LastActivityDate
),
TaggedActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Tags,
    p.Score,
    p.ViewCount,
    pc.CommentCount,
    pc.Body AS HistoryBody,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id) AS LinkCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentTotal
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN (
      SELECT pl.PostId, SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount, MAX(pht.CreationDate) AS LastEdit
      FROM PostHistory ph
      JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
      LEFT JOIN Comments c ON c.PostId = ph.PostId
      GROUP BY pl.PostId
  ) pc ON pc.PostId = p.Id
  WHERE p.PostTypeId = 1
),
WindowStats AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.OwnerUserId,
    r.UpVotes,
    r.DownVotes,
    r.ViewCount,
    r.Score,
    r.LastActivityDate,
    r.Tags,
    ROW_NUMBER() OVER (ORDER BY r.LastActivityDate DESC, r.Score DESC) AS rn
  FROM RecentHot r
),
Combined AS (
  SELECT
    w.PostId,
    w.Title,
    w.CreationDate,
    w.OwnerUserId,
    w.UpVotes,
    w.DownVotes,
    w.ViewCount,
    w.Score,
    w.LastActivityDate,
    w.Tags,
    w.rn,
    ta.OwnerDisplayName,
    ta.Reputation
  FROM WindowStats w
  LEFT JOIN TaggedActivity ta ON ta.PostId = w.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.Reputation,
  c.UpVotes,
  c.DownVotes,
  c.ViewCount,
  c.Score,
  c.Tags,
  c.rn,
  c.HistoryBody,
  c.CommentTotal,
  c.LinkCount
FROM Combined c
WHERE c.rn <= 100
ORDER BY c.rn, c.LastActivityDate DESC;