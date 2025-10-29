-- {"query": "5117.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1024} 
WITH RecentHighActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
),
TagMentions AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
Aggregated AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    u.DisplayName AS Owner,
    u.Reputation,
    v1.Count AS Upvotes,
    v2.Count AS Downvotes,
    c.Count AS CommentCount,
    b.Count AS BadgeCount
  FROM RecentHighActivity r
  LEFT JOIN Users u ON r.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM Votes
    WHERE VoteTypeId = 2 -- UpMod
    GROUP BY PostId
  ) v1 ON v1.PostId = r.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM Votes
    WHERE VoteTypeId = 3 -- DownMod
    GROUP BY PostId
  ) v2 ON v2.PostId = r.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM Comments
    GROUP BY PostId
  ) c ON c.PostId = r.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM PostLinks
    GROUP BY PostId
  ) b ON b.PostId = r.PostId
  WHERE r.rn <= 50
),
Filtered AS (
  SELECT
    a.PostId,
    a.PostTypeId,
    a.Title,
    a.Tags,
    a.CreationDate,
    a.LastActivityDate,
    a.Score,
    a.ViewCount,
    a.Owner,
    a.Reputation,
    a.Upvotes,
    a.Downvotes,
    a.CommentCount,
    a.BadgeCount,
    CASE
      WHEN a.ViewCount = 0 THEN NULL
      ELSE a.Score * 1.0 / a.ViewCount
    END AS EngagementRatio,
    LAG(a.LastActivityDate) OVER (PARTITION BY a.PostTypeId ORDER BY a.LastActivityDate) AS PrevActivity
  FROM Aggregated a
  LEFT JOIN TagMentions t ON CHARINDEX('<' + t.TagName + '>', a.Tags) > 0
  ORDER BY a.LastActivityDate DESC
),
WindowCalc AS (
  SELECT
    p.*,
    SUM(p.Upvotes) OVER (PARTITION BY p.Owner ORDER BY p.LastActivityDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS RollingUpvotes,
    SUM(p.Downvotes) OVER (PARTITION BY p.Owner ORDER BY p.LastActivityDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS RollingDownvotes,
    MAX(p.EngagementRatio) OVER (PARTITION BY p.Owner) AS MaxEngagementByOwner
  FROM Filtered p
)
SELECT
  w.PostId,
  w.PostTypeId,
  w.Title,
  w.Tags,
  w.CreationDate,
  w.LastActivityDate,
  w.Score,
  w.ViewCount,
  w.Owner,
  w.Reputation,
  w.Upvotes,
  w.Downvotes,
  w.CommentCount,
  w.BadgeCount,
  w.EngagementRatio,
  w.PrevActivity,
  w.RollingUpvotes,
  w.RollingDownvotes,
  w.MaxEngagementByOwner,
  (SELECT STRING_AGG(DISTINCT th.Name, ', ')
   FROM PostHistory ph
   JOIN PostHistoryTypes th ON ph.PostHistoryTypeId = th.Id
   WHERE ph.PostId = w.PostId
     AND ph.CreationDate >= w.LastActivityDate - INTERVAL '30 days'
  ) AS RecentHistoryTags
FROM WindowCalc w
LEFT JOIN PostHistory ph ON ph.PostId = w.PostId
LEFT JOIN PostHistoryTypes pon ON ph.PostHistoryTypeId = pon.Id
LEFT JOIN CloseReasonTypes crt ON CAST(NULL AS smallint) IS NOT NULL
WHERE w.Upvotes IS NOT NULL
  AND w.BadgeCount >= 0
ORDER BY w.LastActivityDate DESC
LIMIT 200;