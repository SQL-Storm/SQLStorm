-- {"query": "197.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1515} 
WITH
ActiveUsers AS (
  SELECT Id, Reputation, DisplayName, CreationDate
  FROM Users
  WHERE Reputation > 1000
),
RecentPosts AS (
  SELECT OwnerUserId AS UserId, COUNT(*) AS PostsLast30
  FROM Posts
  WHERE CreationDate >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY OwnerUserId
),
BadgeCounts AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
VotesSummary AS (
  SELECT UserId,
         AVG(COALESCE(BountyAmount,0)) AS AvgBounty,
         SUM(CASE WHEN VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS UpDownVoteCount
  FROM Votes
  GROUP BY UserId
),
TopLinked AS (
  SELECT p.OwnerUserId AS UserId, COUNT(*) AS LinkedPosts
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  GROUP BY p.OwnerUserId
)
SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  COALESCE(r.PostsLast30, 0) AS PostsLast30,
  COALESCE(b.GoldBadges, 0) AS GoldBadges,
  COALESCE(b.SilverBadges, 0) AS SilverBadges,
  COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(v.AvgBounty, 0) AS AvgBounty,
  COALESCE(v.UpDownVoteCount, 0) AS UpDownVoteCount,
  COALESCE(t.LinkedPosts, 0) AS LinkedPosts,
  MAX(p.LastActivityDate) OVER (PARTITION BY u.Id) AS LastActivityDate
FROM ActiveUsers u
LEFT JOIN RecentPosts r ON r.UserId = u.Id
LEFT JOIN BadgeCounts b ON b.UserId = u.Id
LEFT JOIN VotesSummary v ON v.UserId = u.Id
LEFT JOIN TopLinked t ON t.UserId = u.Id
LEFT JOIN Posts p ON p.Id = (
  SELECT Id
  FROM Posts
  WHERE OwnerUserId = u.Id
  ORDER BY CreationDate DESC
  LIMIT 1
)
ORDER BY u.Reputation DESC, u.Id ASC
LIMIT 100;