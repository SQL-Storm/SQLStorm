-- {"query": "14.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 800} 
WITH
-- sample recent activity per post with ranking and windowing
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    COUNT(*) OVER (PARTITION BY p.Id) AS TotalEvents, -- placeholder for activity count
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY v.CreationDate DESC, v.Id DESC) AS rn
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2) -- questions and answers
),
-- correlated subquery to fetch last related post link details
LastLink AS (
  SELECT
    pl.PostId,
    (SELECT TOP 1 ll.RelatedPostId
     FROM PostLinks ll
     WHERE ll.PostId = pl.PostId
     ORDER BY ll.CreationDate DESC) AS LastRelatedPostId,
    (SELECT MAX(lik.LinkTypeId)
     FROM PostLinks lik
     WHERE lik.PostId = pl.PostId) AS MaxLinkType
  FROM Posts pl
),
-- aggregate badge and tag information for Owners
OwnerBadges AS (
  SELECT
    u.Id AS UserId,
    STRING_AGG(CONCAT(b.Name, ' (', b.Class, ')'), ', ') AS BadgesSummary,
    MAX(b.Date) AS LastBadgeDate
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
-- compute a complex derived metric
DerivedMetrics AS (
  SELECT
    ra.PostId,
    ra.Score,
    ra.ViewCount,
    CASE
      WHEN ra.ViewCount > 1000 THEN CAST(ra.Score * 1.25 AS float)
      WHEN ra.ViewCount BETWEEN 500 AND 999 THEN CAST(ra.Score * 1.10 AS float)
      ELSE CAST(ra.Score * 0.95 AS float)
    END AS AdjustedScore,
    CASE
      WHEN ra.PostTypeId = 1 THEN 'Question'
      WHEN ra.PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS PostKind
  FROM RecentActivity ra
)
SELECT
  ra.PostId,
  p.Title,
  p.OwnerDisplayName,
  p.CreationDate,
  p.LastActivityDate,
  p.ViewCount,
  p.Score,
  dm.AdjustedScore,
  dm.PostKind,
  ob.BadgesSummary,
  wl.LastRelatedPostId,
  wl.MaxLinkType,
  -- window function: running total of upvotes by owner
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS UpvotesToDate,
  -- correlated subquery: count comments by owner on this post
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost
FROM
  Posts p
  INNER JOIN DerivedMetrics dm ON dm.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN OwnerBadges ob ON ob.UserId = p.OwnerUserId
  LEFT JOIN LastLink wl ON wl.PostId = p.Id
WHERE
  p.PostTypeId IN (1,2)
  AND p.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
  AND (p.Title LIKE '%benchmark%' OR p.Tags LIKE '%benchmark%')
ORDER BY
  dm.AdjustedScore DESC,
  p.LastActivityDate DESC
LIMIT 100;