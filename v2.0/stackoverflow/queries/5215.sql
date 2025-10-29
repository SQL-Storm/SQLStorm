-- {"query": "5215.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 980}
WITH q AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.FavoriteCount,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditDate,
    pv.RecentVote AS LastVoteType,
    u.Reputation,
    u.DisplayName,
    u.Id AS UserId,
    b.Class AS BadgeClass,
    b.Name AS BadgeName,
    b.Date AS BadgeDate,
    ht.Name AS HistoryType
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT vt.Name AS RecentVote
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.PostId = p.Id
    ORDER BY v.CreationDate DESC
    LIMIT 1
  ) pv ON true
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON u.Id = b.UserId
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN PostHistoryTypes ht ON ph.PostHistoryTypeId = ht.Id
  WHERE
    -- replace placeholder predicate with a reasonable correlated condition:
    -- include posts created or edited within the last 180 days
    (p.CreationDate IS NOT NULL AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY))
    OR (p.LastEditDate IS NOT NULL AND p.LastEditDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY))
),
stats AS (
  SELECT
    p.PostTypeId,
    COUNT(*) AS TotalPosts,
    SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
    AVG(COALESCE(p.Score,0)) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActive,
    STRING_AGG(DISTINCT CAST(p.OwnerUserId AS VARCHAR), ',') AS ActiveUserIds
  FROM Posts p
  GROUP BY p.PostTypeId
),
degenerate AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    (SELECT COUNT(*) FROM Posts c WHERE c.ParentId = p.Id) AS ChildCount,
    (SELECT COUNT(*) FROM Comments co WHERE co.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY)
),
combined AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.Tags,
    q.OwnerUserId,
    q.LastActivityDate,
    q.PostTypeId,
    q.FavoriteCount,
    q.CommentCount,
    q.AcceptedAnswerId,
    q.ParentId,
    q.Body,
    q.LastEditDate,
    q.LastVoteType,
    q.Reputation,
    q.DisplayName,
    q.UserId,
    q.BadgeClass,
    q.BadgeName,
    q.BadgeDate,
    q.HistoryType
  FROM q
  UNION ALL
  SELECT
    d.PostId,
    d.Title,
    NULL AS CreationDate,
    NULL AS ViewCount,
    NULL AS Score,
    d.Tags,
    d.OwnerUserId,
    d.LastActivityDate,
    NULL AS PostTypeId,
    NULL AS FavoriteCount,
    NULL AS CommentCount,
    NULL AS AcceptedAnswerId,
    d.PostId AS ParentId, -- original had d.ParentId which doesn't exist in degenerate; use PostId for ParentId null-equivalent
    NULL AS Body,
    NULL AS LastEditDate,
    NULL AS LastVoteType,
    NULL AS Reputation,
    NULL AS DisplayName,
    NULL AS UserId,
    NULL AS BadgeClass,
    NULL AS BadgeName,
    NULL AS BadgeDate,
    NULL AS HistoryType
  FROM degenerate d
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.Tags,
  c.OwnerUserId,
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.FavoriteCount,
  c.CommentCount,
  c.AcceptedAnswerId,
  c.ParentId,
  c.Body,
  c.LastEditDate,
  c.LastVoteType,
  c.BadgeName,
  c.BadgeDate,
  c.HistoryType
FROM combined c
LEFT JOIN PostLinks pl ON pl.PostId = c.PostId
LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
LEFT JOIN Tags t ON t.Id = (
  CASE
    WHEN c.Tags IS NOT NULL THEN
      (
        SELECT id
        FROM Tags
        WHERE TagName = ANY(string_to_array(REPLACE(REPLACE(c.Tags, '<', ''), '>', ''), ','))
        LIMIT 1
      )
    ELSE NULL
  END
)
WHERE
  (c.Score IS NULL OR c.Score >= -5)
  AND (c.ViewCount IS NULL OR c.ViewCount >= 0)
  AND (c.OwnerUserId IS NULL OR c.OwnerUserId <> -1)
GROUP BY
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.Tags,
  c.OwnerUserId,
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.FavoriteCount,
  c.CommentCount,
  c.AcceptedAnswerId,
  c.ParentId,
  c.Body,
  c.LastEditDate,
  c.LastVoteType,
  c.BadgeName,
  c.BadgeDate,
  c.HistoryType
ORDER BY c.LastActivityDate DESC
LIMIT 100;