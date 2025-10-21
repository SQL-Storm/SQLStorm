-- {"query": "6079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 711} 
WITH
-- 1) recent top users by reputation with a compact activity summary
RecentTopUsers AS (
  SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate,
    U.LastAccessDate,
    U.Location,
    U.Views,
    U.UpVotes,
    U.DownVotes,
    U.AccountId,
    ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS rn
  FROM Users U
  WHERE U.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
-- 2) posts activity per user in the last 30 days (counts by type with NULL-safe expressions)
UserPostActivity AS (
  SELECT
    P.OwnerUserId AS UserId,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(CASE WHEN P.PostTypeId = 5 THEN 1 ELSE 0 END) AS TagWikis,
    SUM(CASE WHEN P.PostTypeId = 4 THEN 1 ELSE 0 END) AS TagWikiExcerpts,
    SUM(CASE WHEN P.PostTypeId IN (1,2) THEN P.Score ELSE 0 END) AS TotalScore,
    COUNT(*) AS TotalPosts
  FROM Posts P
  WHERE P.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    AND P.OwnerUserId IS NOT NULL
  GROUP BY P.OwnerUserId
),
-- 3) top badges earned in the last 90 days by user
UserBadges AS (
  SELECT
    B.UserId,
    COUNT(*) AS BadgeCount,
    MIN(B.Date) AS FirstBadgeDate,
    MAX(B.Date) AS LastBadgeDate
  FROM Badges B
  WHERE B.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
  GROUP BY B.UserId
),
-- 4) weighted activity score using multiple dimensions
WeightedScore AS (
  SELECT
    R.UserId,
    R.DisplayName,
    R.Reputation,
    COALESCE(UP.TotalPosts,0) * 2
      + COALESCE(UP.Questions,0) * 3
      + COALESCE(UP.Answers,0) * 4
      + COALESCE(UP.TagWikis,0) * 1
      + COALESCE(UB.BadgeCount,0) * 5
      + COALESCE(UP.TotalScore,0) * 2 AS ActivityScore
  FROM RecentTopUsers R
  LEFT JOIN UserPostActivity UP ON UP.UserId = R.UserId
  LEFT JOIN UserBadges UB ON UB.UserId = R.UserId
)
SELECT
  WS.UserId,
  WS.DisplayName,
  WS.Reputation,
  WS.ActivityScore,
  RTU.rn AS RankSinceLast30d,
  RTU.LastAccessDate,
  RTU.Location,
  RTU.AccountId,
  RTU.Views,
  RTU.UpVotes,
  RTU.DownVotes,
  RTU.CreationDate
FROM WeightedScore WS
JOIN RecentTopUsers RTU ON RTU.UserId = WS.UserId
ORDER BY WS.ActivityScore DESC, WS.Reputation DESC
LIMIT 100;