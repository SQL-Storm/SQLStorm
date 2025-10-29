-- {"query": "5842.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 992} 
WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.AcceptedAnswerId,
    p.ParentId,
    -- Contained analytics: time since creation
    CAST(JULIANDAY('now') - JULIANDAY(p.CreationDate) AS INTEGER) AS DaysOld
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= (SELECT datetime('now', '-30 days'))
),
TagMetrics AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    SUM(p.Score) AS ScoreSum,
    AVG(p.Score) AS AvgScore,
    SUM(CASE WHEN p.ViewCount > 0 THEN p.ViewCount END) AS TotalViews
  FROM RecentActivePosts rap
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(rap.Tags, 2, length(rap.Tags)-2), '><')) AS TagName
  ) AS tname ON true
  JOIN Tags t ON t.TagName = tname.TagName
  JOIN Posts p ON p.Id = rap.PostId
  GROUP BY t.TagName
),
Engagement AS (
  SELECT
    rp.PostId,
    rp.OwnerUserId,
    rp.Title,
    rp.LastActivityDate,
    v6.CreationDate AS ModeratorViewDate,
    COALESCE(v6.BountyAmount, 0) AS Bounty
  FROM RecentActivePosts rp
  LEFT JOIN Votes v ON v.PostId = rp.PostId AND v.VoteTypeId = 2
  LEFT JOIN Votes v3 ON v3.PostId = rp.PostId AND v3.VoteTypeId = 3
  LEFT JOIN PostHistory ph ON ph.PostId = rp.PostId AND ph.PostHistoryTypeId = 10
  LEFT JOIN Votes v6 ON v6.PostId = rp.PostId AND v6.VoteTypeId = 16
  -- compute a few derived metrics
),
Windowed AS (
  SELECT
    rp.PostId,
    rp.OwnerUserId,
    rp.Title,
    rp.LastActivityDate,
    rp.DaysOld,
    ROW_NUMBER() OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.LastActivityDate DESC) AS rn_by_owner,
    RANK() OVER (ORDER BY rp.LastActivityDate DESC) AS rank_by_activity
  FROM RecentActivePosts rp
),
FinalAudit AS (
  SELECT
    w.PostId,
    w.OwnerUserId,
    w.Title,
    w.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerSince,
    CASE WHEN u.Reputation > 10000 THEN 'Legend' WHEN u.Reputation > 1000 THEN 'Expert' ELSE 'Contributor' END AS RoleTier,
    -- string expression / NULL logic
    CASE
      WHEN u.Location IS NULL THEN 'Unknown'
      WHEN LENGTH(TRIM(u.Location)) = 0 THEN 'Unknown'
      ELSE u.Location
    END AS OwnerLocation,
    CASE
      WHEN p.Tags IS NULL THEN ''
      ELSE p.Tags
    END AS TagsBlob,
    -- json-like placeholder: show a constructed JSON-like string
    CONCAT('{\"PostId\":', w.PostId, ',\"Owner\":', w.OwnerUserId, ',\"DaysOld\":', w.DaysOld, '}') AS MetaJson
  FROM Windowed w
  LEFT JOIN Users u ON u.Id = w.OwnerUserId
  LEFT JOIN Posts p ON p.Id = w.PostId
)
SELECT
  fa.PostId,
  fa.OwnerUserId,
  fa.Title,
  fa.LastActivityDate,
  fa.OwnerDisplayName,
  fa.Reputation,
  fa.OwnerSince,
  fa.RoleTier,
  fa.OwnerLocation,
  fa.TagsBlob,
  fa.MetaJson,
  COALESCE(ve.TotalViews, 0) AS TotalViews,
  COALESCE(e.DaysOld, 0) AS DaysOldAlias
FROM FinalAudit fa
LEFT JOIN (
  SELECT PostId, SUM(ViewCount) AS TotalViews
  FROM Posts
  GROUP BY PostId
) ve ON ve.PostId = fa.PostId
LEFT JOIN Engagement e ON e.PostId = fa.PostId
WHERE fa.RankByActivity IS NULL OR fa.RankByActivity <= 100
ORDER BY fa.LastActivityDate DESC
LIMIT 200;