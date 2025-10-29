-- {"query": "4534.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1032}
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.Comment,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(p.ViewCount) AS TotalViews,
      AVG(p.Score) AS AverageScore,
      MAX(p.CreationDate) AS LastPostCreationDate
    FROM
      Posts p
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.OwnerUserId
  ),
  UserBadgeCounts AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM
      Badges b
    GROUP BY
      b.UserId
  ),
  RecentUserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.LastAccessDate,
      CASE WHEN EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
      ) THEN 1 ELSE 0 END AS WasActiveLastMonth,
      COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
      COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
      COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges
    FROM
      Users u
    LEFT JOIN
      UserBadgeCounts ubc
      ON u.Id = ubc.UserId
    WHERE
      u.CreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
  )
SELECT
  rua.DisplayName,
  rua.Reputation,
  rua.LastAccessDate,
  rua.GoldBadges,
  rua.SilverBadges,
  rua.BronzeBadges,
  upa.QuestionCount,
  upa.TotalViews,
  upa.AverageScore,
  upa.LastPostCreationDate,
  rpe.CreationDate AS LastEditDate,
  rpe.Comment AS LastEditComment,
  CASE
    WHEN rpe.PostHistoryTypeId = 4 THEN 'Title Edit'
    WHEN rpe.PostHistoryTypeId = 5 THEN 'Body Edit'
    WHEN rpe.PostHistoryTypeId = 6 THEN 'Tags Edit'
    ELSE 'Unknown Edit Type'
  END AS LastEditType,
  CASE
    WHEN rua.Reputation BETWEEN 0 AND 99 THEN 'Novice'
    WHEN rua.Reputation BETWEEN 100 AND 499 THEN 'Beginner'
    WHEN rua.Reputation BETWEEN 500 AND 1999 THEN 'Editor'
    WHEN rua.Reputation BETWEEN 2000 AND 9999 THEN 'Participant'
    WHEN rua.Reputation >= 10000 THEN 'Established'
    ELSE 'Unranked'
  END AS ReputationLevel,
  LENGTH(rua.DisplayName) AS DisplayNameLength,
  UPPER(SUBSTRING(rua.DisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
  CASE WHEN rua.WasActiveLastMonth = 1 THEN 'Yes' ELSE 'No' END AS ActiveLastMonth
FROM
  RecentUserActivity rua
LEFT JOIN
  UserPostActivity upa
  ON rua.UserId = upa.OwnerUserId
LEFT JOIN
  RankedPostEdits rpe
  ON rua.UserId = rpe.UserId AND rpe.rn = 1
WHERE
  rua.Reputation > 100
  AND upa.QuestionCount IS NOT NULL
  AND upa.TotalViews > 1000
GROUP BY
  rua.UserId,
  rua.DisplayName,
  rua.Reputation,
  rua.LastAccessDate,
  rua.GoldBadges,
  rua.SilverBadges,
  rua.BronzeBadges,
  upa.OwnerUserId,
  upa.QuestionCount,
  upa.TotalViews,
  upa.AverageScore,
  upa.LastPostCreationDate,
  rpe.CreationDate,
  rpe.Comment,
  rpe.PostHistoryTypeId,
  rua.WasActiveLastMonth
ORDER BY
  rua.Reputation DESC,
  upa.TotalViews DESC;