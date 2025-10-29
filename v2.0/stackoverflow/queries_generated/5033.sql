-- {"query": "5033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 739} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate IS NOT NULL
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS total_score,
    AVG(p.ViewCount) AS avg_views,
    COUNT(*) AS post_count
  FROM Posts p
  JOIN UNNEST(string_to_array(p.Tags, '><')) AS t(TagName) ON TRUE
  GROUP BY t.TagName
),
CorrelatedStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    v.TotalUp AS UpVotesForPost,
    v.TotalDown AS DownVotesForPost,
    c.Name AS CloseReason,
    b.Date AS BadgeDate,
    u.Reputation,
    u.Location,
    u.DisplayName
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VT.Id = 2 THEN 1 ELSE 0 END) AS TotalUp,
                   SUM(CASE WHEN VT.Id = 3 THEN 1 ELSE 0 END) AS TotalDown
    FROM Votes V
    JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    AND ph.PostHistoryTypeId = 10 -- Post Closed
  LEFT JOIN CloseReasonTypes c ON CAST(JSON_VALUE(ph.Text, '$.CloseReasonId') AS SMALLINT) = c.Id
  LEFT JOIN Badges b ON b.TagBased = 0 AND b.UserId = p.OwnerUserId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.LastActivityDate >= NOW() - INTERVAL '60 days'
),
Windowed AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    u.DisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC NULLS LAST, p.ViewCount DESC, p.Score DESC
    ) AS rn_owner
  FROM Posts p
  JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1
)]
SELECT
  rp.PostId,
  rp.Title,
  rp.OwnerUserId,
  rp.ViewCount,
  rp.Score,
  rp.UpVotesForPost,
  rp.DownVotesForPost,
  rp.CloseReason,
  rp.BadgeDate,
  rp.Reputation,
  rp.Location,
  rp.DisplayName,
  wt.TagName,
  wt.total_score,
  wt.avg_views,
  wt.post_count
FROM CorrelatedStats rp
LEFT JOIN TopTags wt ON TRUE
LEFT JOIN Posts p2 ON p2.Id = rp.PostId
LEFT JOIN UnnestTags ut ON ut.PostId = rp.PostId
ORDER BY rp.LastActivityDate DESC
LIMIT 100;