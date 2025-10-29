-- {"query": "5773.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1123} 
WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= DATEADD(year, -2, CURRENT_TIMESTAMP)
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(p.ViewCount) AS TotalViews
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
  ) AS s
  JOIN Tags t ON t.TagName = s.TagName
  GROUP BY t.TagName
),
RecentActivity AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserId,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.CreationDate >= DATEADD(month, -3, CURRENT_TIMESTAMP)
    AND ph.PostHistoryTypeId IN (10,11,16,52,53) -- close/reopen/migrate + hot question events
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
    COUNT(b.Id) AS BadgeCount
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
Joined AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.OwnerUserId,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    tp.PostTypeId,
    ta.TagName,
    ra.LastActivityDate
  FROM TopPosts tp
  LEFT JOIN (
    SELECT
      UNNEST(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName,
      Id AS PostId
    FROM Posts
    WHERE PostTypeId = 1
  ) tgs ON tgs.PostId = tp.PostId
  LEFT JOIN (
    SELECT
      p.Id AS PostId,
      MAX(p.LastActivityDate) AS LastActivityDate
    FROM Posts p
    GROUP BY p.Id
  ) ra ON ra.PostId = tp.PostId
)
SELECT
  t.PostId,
  t.Title,
  t.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  t.CreationDate,
  t.Score,
  t.ViewCount,
  t.Tags,
  t.PostTypeId,
  t.TagName,
  a.HistoryDate AS LastModerationOrMigration,
  a.PostHistoryTypeId,
  u2.UpvotesGiven,
  u2.DownvotesGiven,
  u2.BadgeCount,
  w.TotalViews,
  w.AvgQuestionScore
FROM TopPosts t
LEFT JOIN Users u ON u.Id = t.OwnerUserId
LEFT JOIN (
  SELECT
    ph.PostId,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS HistoryDate,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostHistoryTypeId END) AS PostHistoryTypeId
  FROM PostHistory ph
  GROUP BY ph.PostId
) a ON a.PostId = t.PostId
LEFT JOIN (
  SELECT
    u.Id AS UserId,
    u.DisplayName
  FROM Users u
) u2 ON u2.UserId = t.OwnerUserId
LEFT JOIN (
  SELECT
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    u.Id AS UserId,
    COUNT(b.Id) AS BadgeCount
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
) u2 ON u2.UserId = t.OwnerUserId
LEFT JOIN TagActivity w ON w.TagName = ANY(string_to_array(substring(t.Tags, 2, length(t.Tags)-2), '><'))
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    p.ViewCount AS TotalViews,
    AVG(p.Score) AS AvgQuestionScore
  FROM Posts p
  GROUP BY p.Id, p.ViewCount
) w2 ON w2.PostId = t.PostId
ORDER BY t.CreationDate DESC
LIMIT 100;