-- {"query": "5318.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 700} 
WITH RecentTopPosts AS (
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
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
TopTagVoters AS (
  SELECT
    tt.TagName,
    v.UserId,
    v.CreationDate,
    COUNT(*) OVER (PARTITION BY tt.TagName) AS tagVotes
  FROM Votes v
  JOIN Posts p ON p.Id = v.PostId
  JOIN UNNEST(string_to_array(p.Tags, '>')) AS t(tag) ON true
  JOIN Tags tt ON tt.TagName = trim(BOTH ' <>' FROM p.Tags)
  WHERE v.VoteTypeId = 2 -- UpMod
    AND v.CreationDate >= NOW() - INTERVAL '365 days'
),
Competition AS (
  SELECT
    rtp.PostId,
    rtp.Title,
    rtp.CreationDate,
    rtp.Score,
    rtp.ViewCount,
    rtp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT vl.UserId) AS UniqueVoters,
    AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgBounty,
    MAX(v.CreationDate) AS LastVoteDate
  FROM RecentTopPosts rtp
  LEFT JOIN Votes v ON v.PostId = rtp.PostId
  LEFT JOIN Users u ON u.Id = rtp.OwnerUserId
  LEFT JOIN Votes vl ON vl.PostId = rtp.PostId AND vl.VoteTypeId = 2
  WHERE rtp.rn <= 5
  GROUP BY
    rtp.PostId, rtp.Title, rtp.CreationDate, rtp.Score, rtp.ViewCount,
    rtp.OwnerUserId, u.DisplayName, u.Reputation
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.Reputation,
  c.UniqueVoters,
  c.AvgBounty,
  c.LastVoteDate,
  ht.Name AS HistoryTypeName,
  cl.Name AS CloseReason
FROM Competition c
LEFT JOIN PostHistory ph ON ph.PostId = c.PostId
LEFT JOIN PostHistoryTypes ht ON ht.Id = ph.PostHistoryTypeId
LEFT JOIN PostLinks pl ON pl.PostId = c.PostId
LEFT JOIN CloseReasonTypes cl ON cl.Id = CAST(NULLIF(JSON_VALUE(ph.Text, '$.CloseReasonId'), '') AS smallint)
WHERE
  ph.Id IS NULL OR ph.CreationDate = (
    SELECT MAX(ph2.CreationDate)
    FROM PostHistory ph2
    WHERE ph2.PostId = c.PostId
  )
ORDER BY c.LastVoteDate DESC
LIMIT 100;