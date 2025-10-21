WITH
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
BadgeStats AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesLastYear
  FROM Badges b
  WHERE b.Date >= (CAST('2024-10-01' AS date) - INTERVAL '1 year')
  GROUP BY b.UserId
),
VoteStats AS (
  SELECT
    v.UserId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount,
    SUM(v.BountyAmount) AS TotalBounty
  FROM Votes v
  GROUP BY v.UserId
),
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
    CASE
      WHEN ua.Reputation = 0 THEN NULL
      ELSE (COALESCE(vs.UpModCount,0) - COALESCE(vs.DownModCount,0)) * 1.0 / ua.Reputation
    END AS InfluenceIndex,
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
LastEditPerUser AS (
  SELECT
    a.UserId,
    (
      SELECT ph.CreationDate
      FROM PostHistory ph
      WHERE ph.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = a.UserId
          AND p.LastEditDate IS NOT NULL
        ORDER BY p.Id DESC
        LIMIT 1
      )
      ORDER BY ph.CreationDate DESC
      LIMIT 1
    ) AS LastEditDateCorrelated
  FROM Aggregated a
),
FinalSet AS (
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
  LEFT JOIN (
    SELECT
      p.OwnerUserId AS UserId2,
      SUM(p.ViewCount) AS TotalViews
    FROM Posts p
    GROUP BY p.OwnerUserId
  ) PV ON PV.UserId2 = A.UserId
  WHERE A.LastActivityDate IS NOT NULL
  UNION ALL
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
  COALESCE(LastActivityDate, TIMESTAMP '1970-01-01 00:00:00') AS LastActivityDate,
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