WITH
PostAgg AS (
  SELECT OwnerUserId AS UserId,
         COUNT(*) FILTER (WHERE CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days') AS PostsY365,
         MAX(CreationDate) AS LastPostDate
  FROM Posts
  GROUP BY OwnerUserId
),
CommentAgg AS (
  SELECT UserId,
         COUNT(*) FILTER (WHERE CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days') AS CommentsY365,
         MAX(CreationDate) AS LastCommentDate
  FROM Comments
  GROUP BY UserId
),
BadgeAgg AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
LastActivity AS (
  SELECT u.Id AS UserId,
         GREATEST(COALESCE(p.LastPostDate, TIMESTAMP '1970-01-01 00:00:00'),
                  COALESCE(c.LastCommentDate, TIMESTAMP '1970-01-01 00:00:00'),
                  u.CreationDate) AS LastActivityDate
  FROM Users u
  LEFT JOIN PostAgg p ON p.UserId = u.Id
  LEFT JOIN CommentAgg c ON c.UserId = u.Id
),
Active AS (
  SELECT
     u.Id AS UserId,
     u.DisplayName,
     u.Reputation,
     COALESCE(pa.PostsY365, 0) AS PostsY365,
     COALESCE(ca.CommentsY365, 0) AS CommentsY365,
     COALESCE(ba.GoldBadges, 0) AS GoldBadges,
     COALESCE(ba.SilverBadges, 0) AS SilverBadges,
     COALESCE(ba.BronzeBadges, 0) AS BronzeBadges,
     la.LastActivityDate,
     LOWER(u.DisplayName) || '_' || CAST(u.Id AS VARCHAR) AS DisplayKey
  FROM Users u
  INNER JOIN LastActivity la ON la.UserId = u.Id
  LEFT JOIN PostAgg pa ON pa.UserId = u.Id
  LEFT JOIN CommentAgg ca ON ca.UserId = u.Id
  LEFT JOIN BadgeAgg ba ON ba.UserId = u.Id
  WHERE la.LastActivityDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
),
Inactive AS (
  SELECT
     u.Id AS UserId,
     u.DisplayName,
     u.Reputation,
     0 AS PostsY365,
     0 AS CommentsY365,
     0 AS GoldBadges,
     0 AS SilverBadges,
     0 AS BronzeBadges,
     la.LastActivityDate,
     LOWER(u.DisplayName) || '_' || CAST(u.Id AS VARCHAR) AS DisplayKey
  FROM Users u
  INNER JOIN LastActivity la ON la.UserId = u.Id
  WHERE la.LastActivityDate < TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  PostsY365,
  CommentsY365,
  GoldBadges,
  SilverBadges,
  BronzeBadges,
  LastActivityDate,
  DisplayKey,
  ROW_NUMBER() OVER (ORDER BY LastActivityDate DESC NULLS LAST, Reputation DESC, UserId) AS ActivityRank
FROM (
  SELECT * FROM Active
  UNION ALL
  SELECT * FROM Inactive
) AS AllUsers
ORDER BY LastActivityDate DESC NULLS LAST
LIMIT 200;