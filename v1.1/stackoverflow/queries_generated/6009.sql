-- {"query": "6009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 719} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    -- window: rank by score within 30-day window
    ROW_NUMBER() OVER (
      PARTITION BY DATE(p.CreationDate)
      ORDER BY p.Score DESC, p.ViewCount DESC
    ) AS DayRank
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions only
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTagEngagement AS (
  -- correlate with tag popularity by counting tag occurrences across recent posts
  SELECT
    unnest(string_to_array(p.Tags, '<>')) AS TagName,
    COUNT(*) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN RecentTopPosts rtp ON rtp.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY TagName
),
TagMeta AS (
  SELECT
    t.TagName,
    t.PostCount,
    t.TotalViews,
    t.AvgScore,
    -- correlate with badge presence for tag-based badges
    EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.Name ILIKE '%' || t.TagName || '%'
        AND b.TagBased = 1
    ) AS TagBadgeExists
  FROM TopTagEngagement t
),
CorrelatedHistory AS (
  SELECT
    ph.Id AS HistoryId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Text,
    ph.Comment,
    ph.RevisionGUID
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10,11,12,13,16,52,53) -- notable events
),
FinalOutput AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    jsonb_build_object(
      'dayRank', r.DayRank,
      'TopTags', (SELECT jsonb_agg(jsonb_build_object('Tag', t.TagName, 'Posts', t.PostCount, 'Views', t.TotalViews, 'AvgScore', t.AvgScore, 'HasBadge', t.TagBadgeExists))
                   FROM TagMeta t
                   WHERE t.TagName IN (SELECT unnest(string_to_array(p.Tags, '<>'))))
    ) AS Metadata
  FROM Posts p
  LEFT JOIN RecentTopPosts r ON r.PostId = p.Id
  LEFT JOIN TagMeta tm ON true
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
    AND (p.Score > 0 OR p.ViewCount > 100)
  ORDER BY p.LastActivityDate DESC
  LIMIT 100
)
SELECT
  PostId,
  Title,
  Tags,
  CreationDate,
  Score,
  ViewCount,
  OwnerUserId,
  OwnerDisplayName,
  LastActivityDate,
  Metadata
FROM FinalOutput;