-- {"query": "5894.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 645} 
WITH TagHotness AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    STRING_AGG(DISTINCT CAST(u.Id AS varchar), ',') AS VoterIds
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
  GROUP BY t.TagName
),
ComplexQuery AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    oc.ClosedReason,
    c.CommentCount,
    b.Name AS BadgeName,
    u.DisplayName AS OwnerName,
    v2.UpMod AS UpModImpact
  FROM Posts p
  LEFT JOIN (
      SELECT ph.PostId, ph.Comment AS ClosedReason
      FROM PostHistory ph
      WHERE ph.PostHistoryTypeId = 10
  ) oc ON oc.PostId = p.Id
  LEFT JOIN (
      SELECT PostId, COUNT(*) AS CommentCount
      FROM Comments
      GROUP BY PostId
  ) c ON c.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN (
      SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpMod
      FROM Votes
      GROUP BY PostId
  ) v2 ON v2.PostId = p.Id
  WHERE p.PostTypeId = 1
)
SELECT
  cq.PostId,
  cq.Title,
  cq.CreationDate,
  cq.Score,
  cq.ViewCount,
  cq.OwnerUserId,
  cq.OwnerName,
  cq.Tags,
  cq.LastActivityDate,
  cq.AcceptedAnswerId,
  cq.ClosedReason,
  cq.CommentCount,
  cq.BadgeName,
  th.TagName,
  th.PostCount,
  th.AvgScore,
  th.MaxViews,
  th.UpVotes,
  th.DownVotes,
  th.VoterIds,
  cq.UpModImpact
FROM ComplexQuery cq
LEFT JOIN TagHotness th
  ON th.TagName = ANY(string_to_array(REGEXP_REPLACE(cq.Tags, '<|>|\\(|\\)|\"', '', 'g'), ','))
ORDER BY cq.LastActivityDate DESC
LIMIT 200;