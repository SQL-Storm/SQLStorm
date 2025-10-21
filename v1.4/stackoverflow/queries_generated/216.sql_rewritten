-- {"query": "216.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 11032} 
WITH
UserBase AS (
  SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, '') AS Location,
    COALESCE(u.UpVotes, 0) AS UpVotes,
    COALESCE(u.DownVotes, 0) AS DownVotes
  FROM Users u
),
UserPostStats AS (
  SELECT
    b.UserId,
    COUNT(p.Id) AS PostCount,
    AVG(COALESCE(p.Score,0)) AS AvgPostScore,
    SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM UserBase b
  LEFT JOIN Posts p ON p.OwnerUserId = b.UserId
  GROUP BY b.UserId
),
UserBadgeStats AS (
  SELECT
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
UserCommentStats AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(c.Id) AS TotalComments
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.OwnerUserId
),
UserLatestPost AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.Id AS PostId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(uc.TotalComments, 0) AS TotalComments,
  pu.PostCount,
  pu.AvgPostScore,
  pu.TotalViews,
  COALESCE(ub.GoldBadges, 0) AS GoldBadges,
  COALESCE(ub.SilverBadges, 0) AS SilverBadges,
  COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
  ub.LastBadgeDate,
  ul.LastActivityDate AS LatestPostDate,
  ul.PostId AS LatestPostId,
  (
     SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     WHERE ph.PostId = (
        SELECT Id FROM Posts
        WHERE OwnerUserId = u.UserId
        ORDER BY CreationDate DESC
        LIMIT 1
     )
  ) AS LastPostHistoryDate,
  COALESCE((
     SELECT STRING_AGG(DISTINCT TagName, ',')
     FROM (
       SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
       FROM Posts p
       WHERE p.OwnerUserId = u.UserId AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
     ) t
  ), '') AS TopTags
FROM UserBase u
LEFT JOIN UserPostStats pu ON pu.UserId = u.UserId
LEFT JOIN UserCommentStats uc ON uc.UserId = u.UserId
LEFT JOIN UserBadgeStats ub ON ub.UserId = u.UserId
LEFT JOIN (
  SELECT UserId, PostId, LastActivityDate
  FROM UserLatestPost
  WHERE rn = 1
) ul ON ul.UserId = u.UserId
WHERE
  -- Block 1: high reputation users
  u.Reputation > 1500

UNION ALL

SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(uc.TotalComments, 0) AS TotalComments,
  pu.PostCount,
  pu.AvgPostScore,
  pu.TotalViews,
  COALESCE(ub.GoldBadges, 0) AS GoldBadges,
  COALESCE(ub.SilverBadges, 0) AS SilverBadges,
  COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
  ub.LastBadgeDate,
  ul.LastActivityDate AS LatestPostDate,
  ul.PostId AS LatestPostId,
  (
     SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     WHERE ph.PostId = (
        SELECT Id FROM Posts
        WHERE OwnerUserId = u.UserId
        ORDER BY CreationDate DESC
        LIMIT 1
     )
  ) AS LastPostHistoryDate,
  COALESCE((
     SELECT STRING_AGG(DISTINCT TagName, ',')
     FROM (
       SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
       FROM Posts p
       WHERE p.OwnerUserId = u.UserId AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
     ) t
  ), '') AS TopTags
FROM UserBase u
LEFT JOIN UserPostStats pu ON pu.UserId = u.UserId
LEFT JOIN UserCommentStats uc ON uc.UserId = u.UserId
LEFT JOIN UserBadgeStats ub ON ub.UserId = u.UserId
LEFT JOIN (
  SELECT UserId, PostId, LastActivityDate
  FROM UserLatestPost
  WHERE rn = 1
) ul ON ul.UserId = u.UserId
WHERE
  (u.Reputation <= 1500)
  AND u.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
ORDER BY LatestPostDate DESC NULLS LAST
;