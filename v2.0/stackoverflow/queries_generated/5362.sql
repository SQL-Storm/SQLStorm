-- {"query": "5362.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 885} 
WITH
RecentPostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_owner
  FROM Posts p
  WHERE p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '180 days'
),
TopActiveOwners AS (
  SELECT
    r.OwnerUserId,
    COUNT(*) AS posts_last_180_days,
    SUM(r.ViewCount) AS total_views,
    AVG(r.Score) AS avg_score,
    SUM(CASE WHEN r.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions
  FROM RecentPostActivity r
  WHERE r.rn_by_owner = 1
  GROUP BY r.OwnerUserId
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(p.ViewCount) AS total_views,
    AVG(p.Score) AS avg_score,
    COUNT(*) AS post_count
  FROM Posts p
  CROSS APPLY string_to_array(p.Tags, ',') AS ta
  CROSS APPLY unnest(string_to_array(p.Tags, ',') ) AS tname(tag)
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY total_views DESC
  LIMIT 50
),
FlaggedByModerators AS (
  SELECT
    v.PostId,
    v.UserId AS ModeratorUserId,
    v.VoteTypeId,
    v.CreationDate,
    u.Reputation
  FROM Votes v
  JOIN Users u ON u.Id = v.UserId
  WHERE v.VoteTypeId IN (14, 15) -- Moderator related votes
),
PostHistorySummary AS (
  SELECT
    ph.PostId,
    MAX(CASE WHEN pht.Name = 'Post Closed' THEN ph.CreationDate END) AS last_close_date,
    MAX(CASE WHEN pht.Name = 'Post Reopened' THEN ph.CreationDate END) AS last_reopen_date,
    MAX(CASE WHEN pht.Name = 'Post Deleted' THEN ph.CreationDate END) AS last_delete_date
  FROM PostHistory ph
  JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
  GROUP BY ph.PostId
),
Combined AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.OwnerUserId,
    r.LastActivityDate,
    r.ViewCount,
    r.Score,
    r.Tags,
    h.last_close_date,
    h.last_reopen_date,
    h.last_delete_date,
    t.total_views AS total_views_for_post,
    t.avg_score AS avg_post_score
  FROM RecentPostActivity r
  LEFT JOIN PostHistorySummary h ON h.PostId = r.PostId
  LEFT JOIN (
    SELECT
      p.Id AS PostId,
      SUM(p.ViewCount) OVER (PARTITION BY p.Id) AS total_views,
      AVG(p.Score) OVER (PARTITION BY p.Id) AS avg_score
    FROM Posts p
  ) t ON t.PostId = r.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.PostTypeId,
  c.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.Tags,
  c.last_close_date,
  c.last_reopen_date,
  c.last_delete_date,
  b.Name AS BadgeName,
  b.Date AS BadgeDate,
  v.ModeratorUserId,
  v.VoteTypeId,
  v.CreationDate AS VoteDate
FROM Combined c
LEFT JOIN Users u ON u.Id = c.OwnerUserId
LEFT JOIN Badges b ON b.UserId = u.Id AND b.Class = 1
LEFT JOIN FlaggedByModerators v ON v.PostId = c.PostId
ORDER BY
  c.LastActivityDate DESC,
  c.ViewCount DESC
LIMIT 100;