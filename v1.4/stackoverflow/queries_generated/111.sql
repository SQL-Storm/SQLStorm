-- {"query": "111.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2833} 
WITH
-- 1) Per-user latest activity metrics and a last question post (if any)
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    MAX(p.LastActivityDate) AS LastActivityDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- 2) For each user, their most recent Question (PostTypeId = 1), if exists
LatestQuestion AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.Title AS LatestQuestionTitle,
    p.CreationDate AS LatestQuestionDate,
    p.Id AS LatestQuestionId,
    p.Score AS LatestQuestionScore,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC, p.Id DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
-- 3) Per-user badge counts (last year)
BadgeStats AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesLastYear
  FROM Badges b
  WHERE b.Date >= (CURRENT_DATE - INTERVAL '1 year')
  GROUP BY b.UserId
),
-- 4) Per-user vote activity split by UpMod and DownMod (and NULL-safe)
VoteStats AS (
  SELECT
    v.UserId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount,
    SUM(v.BountyAmount) AS TotalBounty
  FROM Votes v
  GROUP BY v.UserId
),
-- 5) Outer join path simulating complex correlations with subqueries and window
Aggregated AS (
  SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.LastActivityDate,
    COALESCE(lq.LatestQuestionTitle, NULL) AS LastQuestionTitle,
    COALESCE(lq.LatestQuestionDate, NULL) AS LastQuestionDate,
    COALESCE(vs.UpModCount, 0) AS UpModCount,
    COALESCE(vs.DownModCount, 0) AS DownModCount,
    COALESCE(bs.BadgesLastYear, 0) AS BadgesLastYear,
    -- derive a NULL-safe ratio with conditional expression
    CASE
      WHEN ua.Reputation = 0 THEN NULL
      ELSE (COALESCE(vs.UpModCount,0) - COALESCE(vs.DownModCount,0))::float / ua.Reputation
    END AS InfluenceIndex,
    -- a window function example: rank within reputation groups
    RANK() OVER (
      PARTITION BY DATE_TRUNC('year', ua.LastActivityDate)
      ORDER BY ua.Reputation DESC, ua.LastActivityDate DESC
    ) AS YearRank
  FROM UserActivity ua
  LEFT JOIN LatestQuestion lq
    ON lq.UserId = ua.UserId AND lq.rn = 1
  LEFT JOIN VoteStats vs ON vs.UserId = ua.UserId
  LEFT JOIN BadgeStats bs ON bs.UserId = ua.UserId
),
-- 6) A correlated subquery surface: last edited post timestamp per user via PostHistory
LastEditPerUser AS (
  SELECT
    a.UserId,
    (SELECT ph.CreationDate
     FROM PostHistory ph
     WHERE ph.PostId = (SELECT p.Id
                        FROM Posts p
                        WHERE p.OwnerUserId = a.UserId
                          AND p.LastEditDate IS NOT NULL
                          AND p.Id = p.Id) -- placeholder for correlated path
     ORDER BY ph.CreationDate DESC
     LIMIT 1) AS LastEditDateCorrelated
  FROM Aggregated a
),
-- 7) Final selection using a mix of inner/outer joins, correlated subquery and set operators
FinalSet AS (
  -- Part A: primary performance benchmark slice
  SELECT
    A.UserId,
    A.DisplayName,
    A.Reputation,
    A.LastActivityDate,
    A.LastQuestionTitle,
    A.LastQuestionDate,
    A.UpModCount,
    A.DownModCount,
    A.BadgesLastYear,
    A.InfluenceIndex,
    A.YearRank,
    LEE.LastEditDateCorrelated
  FROM Aggregated A
  LEFT JOIN LastEditPerUser LEE ON LEE.UserId = A.UserId
  -- include a page-view like metric via a nested correlated subquery
  LEFT JOIN (
    SELECT
      p.OwnerUserId AS UserId2,
      SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    GROUP BY p.OwnerUserId
  ) PV ON PV.UserId2 = A.UserId
  WHERE A.LastActivityDate IS NOT NULL
  UNION ALL
  -- Part B: alternate slice to stress planner with more complex predicates and NULL handling
  SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    NULL AS LastActivityDate,
    NULL AS LastQuestionTitle,
    NULL AS LastQuestionDate,
    0 AS UpModCount,
    0 AS DownModCount,
    0 AS BadgesLastYear,
    NULL AS InfluenceIndex,
    NULL AS YearRank,
    NULL AS LastEditDateCorrelated
  FROM Users U
  WHERE U.Reputation > 100000
  LIMIT 10
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  COALESCE(LastActivityDate, TIMESTAMP 'epoch') AS LastActivityDate,
  LastQuestionTitle,
  LastQuestionDate,
  UpModCount,
  DownModCount,
  BadgesLastYear,
  InfluenceIndex,
  YearRank,
  LastEditDateCorrelated
FROM FinalSet
ORDER BY Reputation DESC NULLS LAST, LastActivityDate DESC NULLS LAST
LIMIT 200;