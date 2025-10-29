WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      upa.TotalPosts,
      upa.Questions,
      upa.Answers,
      upa.AvgPostScore,
      upa.LastPostDate,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadges,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2
      ) AS SilverBadges,
      (
        SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3
      ) AS BronzeBadges,
      (
        SELECT
          '{' ||
          '"Id": "' || COALESCE(CAST(prev.Id AS VARCHAR), '') || '", ' ||
          '"DisplayName": "' || COALESCE(prev.DisplayName, '') || '"' ||
          '}'
        FROM Users prev
        WHERE prev.Id = u.Id - 1
      ) AS PreviousUser
    FROM Users u
    JOIN UserPostActivity upa
      ON u.Id = upa.OwnerUserId
    WHERE
      u.Reputation > 100000
  )
SELECT
  hru.DisplayName AS UserDisplayName,
  hru.Reputation,
  hru.TotalPosts,
  hru.Questions,
  hru.Answers,
  hru.AvgPostScore,
  hru.LastPostDate,
  hru.GoldBadges,
  hru.SilverBadges,
  hru.BronzeBadges,
  CASE
    WHEN hru.DisplayName IS NULL THEN 'Unknown'
    WHEN CHAR_LENGTH(hru.DisplayName) > 10 THEN SUBSTRING(hru.DisplayName FROM 1 FOR 10) || '...'
    ELSE hru.DisplayName
  END AS TruncatedDisplayName,
  CASE
    WHEN hru.LastPostDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY) THEN 'Inactive'
    ELSE 'Active'
  END AS UserActivityStatus,
  (
    SELECT COUNT(*)
    FROM RankedPostEdits rpe
    WHERE rpe.UserId = hru.UserId AND rpe.rn = 1
  ) AS MostRecentEdits,
  COALESCE(
    (SELECT DisplayName FROM Users u2 WHERE u2.Id = hru.UserId - 1),
    'No Previous User'
  ) AS PreviousUserDisplayName,
  (
    SELECT COUNT(DISTINCT ph.PostId)
    FROM PostHistory ph
    WHERE ph.UserId = hru.UserId AND ph.PostHistoryTypeId = 16
  ) AS PostsPutToCommunityWiki
FROM HighReputationUsers hru
WHERE
  hru.Reputation BETWEEN 100000 AND 500000
  AND hru.LastPostDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)

UNION ALL

SELECT
  'Total' AS UserDisplayName,
  SUM(hru.Reputation) AS Reputation,
  SUM(hru.TotalPosts) AS TotalPosts,
  SUM(hru.Questions) AS Questions,
  SUM(hru.Answers) AS Answers,
  AVG(hru.AvgPostScore) AS AvgPostScore,
  MAX(hru.LastPostDate) AS LastPostDate,
  SUM(hru.GoldBadges) AS GoldBadges,
  SUM(hru.SilverBadges) AS SilverBadges,
  SUM(hru.BronzeBadges) AS BronzeBadges,
  'N/A' AS TruncatedDisplayName,
  'N/A' AS UserActivityStatus,
  COUNT(DISTINCT rpe.PostId) AS MostRecentEdits,
  'N/A' AS PreviousUserDisplayName,
  COUNT(DISTINCT ph.PostId) AS PostsPutToCommunityWiki
FROM HighReputationUsers hru
LEFT JOIN RankedPostEdits rpe
  ON hru.UserId = rpe.UserId AND rpe.rn = 1
LEFT JOIN PostHistory ph
  ON hru.UserId = ph.UserId AND ph.PostHistoryTypeId = 16
WHERE
  hru.Reputation BETWEEN 100000 AND 500000
  AND hru.LastPostDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY
  -- group by all non-aggregated selected expressions
  'Total';