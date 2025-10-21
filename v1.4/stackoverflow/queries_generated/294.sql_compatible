WITH
UserBase AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate AS CreationDate,
         u.LastAccessDate,
         u.Location,
         u.AboutMe
  FROM Users u
),
UserStats AS (
  SELECT ub.UserId,
         ub.DisplayName,
         ub.Reputation,
         ub.CreationDate,
         ub.LastAccessDate,
         ub.Location,
         COALESCE(SUM(p.ViewCount),0) AS TotalViews,
         COALESCE(COUNT(p.Id),0) AS PostCount,
         COALESCE(SUM(p.Score),0) AS ScoreSum,
         MAX(p.LastActivityDate) AS LastActivityDate
  FROM UserBase ub
  LEFT JOIN Posts p ON p.OwnerUserId = ub.UserId
  GROUP BY ub.UserId, ub.DisplayName, ub.Reputation, ub.CreationDate, ub.LastAccessDate, ub.Location
),
UserBadges AS (
  SELECT b.UserId,
         STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS Badges
  FROM Badges b
  GROUP BY b.UserId
),
TopTagPerUser AS (
  SELECT u.UserId,
         COALESCE(tt.TagName, '') AS TopTag
  FROM (
     SELECT u.Id AS UserId
     FROM Users u
  ) AS u
  LEFT JOIN LATERAL (
     SELECT TagName
     FROM Posts p
     CROSS JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
     WHERE p.OwnerUserId = u.UserId
     GROUP BY TagName
     ORDER BY COUNT(*) DESC
     LIMIT 1
  ) AS tt(TagName) ON TRUE
),
Ranked AS (
  SELECT us.UserId,
         us.DisplayName,
         us.Reputation,
         us.CreationDate,
         us.LastAccessDate,
         us.Location,
         us.TotalViews,
         us.PostCount,
         us.ScoreSum,
         us.LastActivityDate,
         COALESCE(ub.Badges, '') AS Badges,
         COALESCE(tt.TopTag, '') AS TopTag,
         ROW_NUMBER() OVER (ORDER BY us.TotalViews DESC, us.Reputation DESC) AS Rank
  FROM UserStats us
  LEFT JOIN UserBadges ub ON ub.UserId = us.UserId
  LEFT JOIN TopTagPerUser tt ON tt.UserId = us.UserId
)
SELECT *
FROM Ranked
ORDER BY Rank
LIMIT 150;