-- {"query": "295.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 10186} 
WITH
year_posts AS (
  SELECT OwnerUserId AS UserId,
         COUNT(*) AS PostCountYear,
         COALESCE(SUM(Score), 0) AS ScoreYear,
         MAX(LastActivityDate) AS LastActivity
  FROM Posts
  WHERE CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  GROUP BY OwnerUserId
),
user_badges AS (
  SELECT UserId,
         COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
         COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
         COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
user_votes AS (
  SELECT UserId,
         COUNT(*) AS VoteCountLastYear,
         COALESCE(SUM(BountyAmount), 0) AS TotalBounty
  FROM Votes
  WHERE CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  GROUP BY UserId
),
set1 AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COALESCE(y.PostCountYear, 0) AS PostCountYear,
         COALESCE(y.ScoreYear, 0) AS ScoreYear,
         COALESCE(b.GoldBadges, 0) AS GoldBadges,
         COALESCE(b.SilverBadges, 0) AS SilverBadges,
         COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
         COALESCE(v.VoteCountLastYear, 0) AS VoteCountLastYear,
         COALESCE(v.TotalBounty, 0) AS TotalBounty,
         u.Reputation,
         u.LastAccessDate,
         u.Location,
         (u.AccountId IS NULL) AS AccountMissing,
         (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCountByUser,
         CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE TRIM(u.Location) END AS LocationTrim,
         'active_year' AS Phase
  FROM Users u
  LEFT JOIN year_posts y ON y.UserId = u.Id
  LEFT JOIN user_badges b ON b.UserId = u.Id
  LEFT JOIN user_votes v ON v.UserId = u.Id
),
set2 AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         0 AS PostCountYear,
         0 AS ScoreYear,
         COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1), 0) AS GoldBadges,
         COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2), 0) AS SilverBadges,
         COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3), 0) AS BronzeBadges,
         0 AS VoteCountLastYear,
         0 AS TotalBounty,
         u.Reputation,
         u.LastAccessDate,
         u.Location,
         (u.AccountId IS NULL) AS AccountMissing,
         (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCountByUser,
         CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE TRIM(u.Location) END AS LocationTrim,
         'prestige' AS Phase
  FROM Users u
  WHERE u.Reputation > 1000
)
SELECT UserId, DisplayName, PostCountYear, ScoreYear, GoldBadges, SilverBadges, BronzeBadges,
       VoteCountLastYear, TotalBounty, Reputation, LastAccessDate, Location, AccountMissing,
       CommentCountByUser, LocationTrim, Phase
FROM (
  SELECT *
  FROM (
    SELECT * FROM set1
    UNION ALL
    SELECT * FROM set2
  ) AS allset
) AS base
ORDER BY Reputation DESC NULLS LAST, LastAccessDate DESC NULLS LAST
LIMIT 400;