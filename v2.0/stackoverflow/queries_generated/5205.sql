-- {"query": "5205.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1090} 
WITH
-- 1) Top contributing users by reputation with recent activity and badge count
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AboutMe,
    u.ProfileImageUrl,
    COALESCE(b.TotalBadges, 0) AS BadgeCount,
    COUNT(p.Id) FILTER (WHERE p.CreationDate > NOW() - INTERVAL '30 days') AS PostsLast30d
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, b.TotalBadges
),
-- 2) Posts with complex calculations: score-weighted viewership and derived flags
PostAnalytics AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    CASE
      WHEN p.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id)
      ELSE 0
    END AS CommentCount,
    CASE
      WHEN p.ClosedDate IS NOT NULL THEN true
      ELSE false
    END AS IsClosed,
    CASE
      WHEN p.AnswerCount > 0 THEN p.AnswerCount
      ELSE (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) 
    END AS AnswerCountDerived,
    -- Correlated subquery: latest revision by last editor
    (SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     WHERE ph.PostId = p.Id AND ph.UserId IS NOT NULL) AS LastRevisionDate
  FROM Posts p
),
-- 3) Complex windowed metrics per user: cumulative score over time
UserScoreWindow AS (
  SELECT
    p.OwnerUserId,
    p.Id AS PostId,
    p.Score,
    p.CreationDate,
    SUM(p.Score) OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CumulativeScore
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
),
-- 4) Explore cross-join style correlations with tag-wiki and tag-links
TagRelations AS (
  SELECT
    t.TagName,
    tl.RelatedTagName,
    COUNT(*) AS CoOccurrence
  FROM Tags t
  JOIN PostLinks pl ON pl.PostId = t.WikiPostId OR pl.RelatedPostId = t.WikiPostId
  JOIN Tags tl ON tl.TagName = (SELECT unnest(string_to_array(pl.PostId::text, ',')) LIMIT 1)
  GROUP BY t.TagName, tl.RelatedTagName
),
-- 5) Complex predicate set: posts satisfying various nuanced criteria
FilteredPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount
  FROM Posts p
  WHERE
    (p.PostTypeId = 1 OR p.PostTypeId = 2)
    AND (p.ViewCount > 1000 OR p.Score > 5)
    AND EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = p.Id AND v.VoteTypeId = 2
      AND v.CreationDate > p.CreationDate - INTERVAL '180 days'
    )
    AND NOT EXISTS (
      SELECT 1
      FROM PostHistory ph
      WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 -- post closed
      AND ph.CreationDate > NOW() - INTERVAL '365 days'
    )
)
SELECT
  -- Summary of benchmarking-relevant metrics
  ua.Id AS UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.BadgeCount,
  ra.PostsLast30d,
  pa.PostId,
  pa.PostTypeId,
  pa.Title,
  pa.Tags,
  pa.Score,
  pa.ViewCount,
  pa.CommentCount,
  pa.IsClosed,
  pa.LastRevisionDate,
  uw.CumulativeScore AS UserCumulativeScore,
  tr.TagName,
  tr.RelatedTagName,
  tr.CoOccurrence
FROM RecentActivity ua
LEFT JOIN PostAnalytics pa ON pa.OwnerUserId = ua.Id
LEFT JOIN UserScoreWindow uw ON uw.OwnerUserId = ua.Id AND uw.PostId = pa.PostId
LEFT JOIN TagRelations tr ON true
LEFT JOIN FilteredPosts fp ON fp.OwnerUserId = ua.Id AND fp.PostId = pa.PostId
ORDER BY ua.Reputation DESC, pa.Score DESC
LIMIT 200;