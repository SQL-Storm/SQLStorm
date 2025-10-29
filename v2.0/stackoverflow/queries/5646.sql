-- {"query": "5646.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 980}
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
),
PostMetrics AS (
  SELECT
    r.PostId,
    r.Title,
    r.PostCreationDate,
    r.LastActivityDate,
    r.OwnerUserId,
    r.OwnerDisplayName,
    r.Score,
    r.ViewCount,
    r.Tags,
    r.PostTypeId,
    (
      COALESCE(r.ViewCount, 0) * 1.0
      + COALESCE(r.Score, 0) * 2.5
      + (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - r.PostCreationDate)) / 86400.0) * -0.5
      + (CASE WHEN r.Tags ~ '\b(''c#''|''sql''|''postgresql''|''window'')' THEN 5 ELSE 0 END)
    ) AS EngineeredScore
  FROM RecentActivity r
  WHERE r.rn = 1
),
UserBadgeStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(DISTINCT v.PostId) AS UpvotedPosts
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId = 2
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserPostWindow AS (
  SELECT
    pm.PostId,
    pm.Title,
    pm.OwnerUserId,
    pm.PostTypeId,
    pm.EngineeredScore,
    ROW_NUMBER() OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.EngineeredScore DESC) AS UserRank
  FROM PostMetrics pm
)
SELECT
  upw.PostId,
  upw.Title,
  upw.PostTypeId,
  pt.Name AS PostTypeName,
  upw.EngineeredScore,
  upw.UserRank,
  u.Id AS UserId,
  u.DisplayName AS UserDisplayName,
  u.Reputation,
  ub.BadgeCount,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  ub.UpvotedPosts,
  plmw.RelatedPostId,
  plmw.LinkTypeName,
  (
    SELECT STRING_AGG(CONCAT(p2.Id, ':', p2.Title), ';')
    FROM PostLinks pl
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE pl.PostId = upw.PostId
  ) AS RelatedPostsInfo
FROM UserPostWindow upw
JOIN PostTypes pt ON upw.PostTypeId = pt.Id
JOIN Users u ON upw.OwnerUserId = u.Id
LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
LEFT JOIN PostLinks plw ON plw.PostId = upw.PostId
LEFT JOIN (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
) plmw ON plmw.PostId = upw.PostId
WHERE upw.EngineeredScore > 0
  AND upw.UserRank <= 10
ORDER BY upw.EngineeredScore DESC, upw.UserRank ASC
LIMIT 100;