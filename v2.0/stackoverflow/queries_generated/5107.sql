-- {"query": "5107.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 902} 
WITH
-- recent activity per post with a complex windowed ranking
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC, p.Score DESC, p.ViewCount DESC
    ) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate IS NOT NULL
),
-- correlate with user metadata and badge activity
UserBadgeStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(b.Id) AS BadgeCount,
    MAX(b.Date) AS LastBadgeDate,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- compute a complex derived metric for each post
PostMetrics AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerUserId,
    ra.Tags,
    U.UserId,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation AS OwnerReputation,
    B.BadgeCount,
    B.LastBadgeDate,
    B.GoldBadges,
    -- derived k-factor: weighted combination with potential NULL-safe ops
    COALESCE(ra.Score, 0) * 0.7
    + COALESCE(ra.ViewCount, 0) * 0.2
    + COALESCE(B.GoldBadges, 0) * 1.5
    + (CASE WHEN ra.LastActivityDate > NOW() - INTERVAL '180 days' THEN 2 ELSE 0 END) AS PerformanceIndex
  FROM RecentActivity ra
  LEFT JOIN Users U ON U.Id = ra.OwnerUserId
  LEFT JOIN UserBadgeStats B ON B.UserId = U.Id
),
-- filter to top performers with a cross-join style predicate
TopPosts AS (
  SELECT
    pm.*,
    NTILE(5) OVER (ORDER BY pm.PerformanceIndex DESC) AS Quintile
  FROM PostMetrics pm
  WHERE pm.ViewCount > 0
    AND pm.Score IS NOT NULL
    AND pm.OwnerReputation > 0
)
SELECT
  tp.PostId,
  tp.Title,
  tp.OwnerDisplayName,
  tp.OwnerReputation,
  tp.ViewCount,
  tp.Score,
  tp.LastActivityDate,
  tp.Tags,
  tp.Quintile,
  CASE
    WHEN tp.Quintile = 1 THEN 'Top-20%'
    WHEN tp.Quintile = 2 THEN 'Next-20%'
    WHEN tp.Quintile = 3 THEN 'Mid-20%'
    WHEN tp.Quintile = 4 THEN 'Bottom-20%'
    ELSE 'Bottom-20+'
  END AS Segment,
  -- complex string expression: make a compact signature
  CONCAT('[', tp.PostId, '] ', COALESCE(tp.Title, ''), ' by ', COALESCE(tp.OwnerDisplayName, 'Unknown')) AS Signature,
  -- nested correlated subquery: count of related links that are duplicates
  (SELECT COUNT(*) FROM PostLinks pl
     WHERE pl.PostId = tp.PostId
       AND pl.RelatedPostId IS NOT NULL
       AND EXISTS (
         SELECT 1
         FROM LinkTypes lt
         WHERE lt.Id = pl.LinkTypeId
           AND lt.Name ILIKE '%Duplicate%'
       )
  ) AS DuplicateRelatedLinks,
  -- existence of a comment with a NULL user
  EXISTS (
    SELECT 1
    FROM Comments c
    WHERE c.PostId = tp.PostId
      AND (c.UserId IS NULL OR c.UserId = 0)
  ) AS HasNullUserComment
FROM TopPosts tp
ORDER BY tp.PerformanceIndex DESC, tp.LastActivityDate DESC
LIMIT 100;