WITH UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
  SELECT
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges b
  GROUP BY b.UserId
),
LinkCounts AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(pl.Id) AS TotalLinks,
    SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedCount,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCount
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  GROUP BY p.OwnerUserId
),
LatestPostInfo AS (
  SELECT
    p.OwnerUserId AS UserId,
    MAX(p.LastActivityDate) AS LastActivityDate,
    MAX(CASE WHEN p.Title IS NOT NULL THEN LENGTH(p.Title) ELSE NULL END) AS MaxTitleLen
  FROM Posts p
  GROUP BY p.OwnerUserId
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.TotalPosts,
  ua.Questions,
  ua.Answers,
  ua.TotalViews,
  ua.AvgScore,
  ua.LastActivity,
  COALESCE(bs.GoldBadges, 0) AS GoldBadges,
  COALESCE(bs.SilverBadges, 0) AS SilverBadges,
  COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(lc.TotalLinks, 0) AS TotalLinks,
  COALESCE(lc.LinkedCount, 0) AS LinkedCount,
  COALESCE(lc.DuplicateCount, 0) AS DuplicateCount,
  COALESCE(lp.MaxTitleLen, 0) AS MaxTitleLen,
  COALESCE(lp.LastActivityDate, ua.LastActivity) AS LastPostDate
FROM UserActivity ua
LEFT JOIN BadgeStats bs ON bs.UserId = ua.UserId
LEFT JOIN LinkCounts lc ON lc.UserId = ua.UserId
LEFT JOIN LatestPostInfo lp ON lp.UserId = ua.UserId
ORDER BY TotalViews DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;