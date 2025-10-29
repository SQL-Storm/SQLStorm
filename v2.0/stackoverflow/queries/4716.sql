WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostCounts AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserEditFrequency AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS DistinctEditedPosts,
      COUNT(*) AS TotalEdits,
      AVG(EXTRACT(EPOCH FROM rpe.EditDate)) AS AvgEditTimestampEpoch
    FROM
      RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
  ),
  CommunityActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT c.PostId) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      AVG(EXTRACT(EPOCH FROM c.CreationDate)) AS AvgCommentDateEpoch
    FROM
      Comments AS c
      JOIN Posts AS p ON c.PostId = p.Id
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views AS UserViews,
      upc.PostCount,
      upc.QuestionCount,
      upc.AnswerCount,
      upc.AvgPostScore,
      uef.TotalEdits,
      ca.CommentCount,
      ca.TotalCommentScore,
      p.Tags AS MostFrequentTag
    FROM
      Users AS u
      LEFT JOIN UserPostCounts AS upc ON u.Id = upc.OwnerUserId
      LEFT JOIN UserEditFrequency AS uef ON u.Id = uef.UserId
      LEFT JOIN CommunityActivity AS ca ON u.Id = ca.OwnerUserId
      LEFT JOIN (
        SELECT
          OwnerUserId,
          Tags,
          ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY COUNT(*) DESC) as rn
        FROM
          Posts
        WHERE OwnerUserId IS NOT NULL AND Tags IS NOT NULL
        GROUP BY OwnerUserId, Tags
      ) as p ON u.Id = p.OwnerUserId AND p.rn = 1
    WHERE
      u.Reputation > 10000
  )
SELECT
  hru.DisplayName,
  hru.Reputation,
  hru.CreationDate,
  hru.UserViews,
  hru.PostCount,
  hru.QuestionCount,
  hru.AnswerCount,
  hru.AvgPostScore,
  hru.TotalEdits,
  hru.CommentCount,
  hru.TotalCommentScore,
  hru.MostFrequentTag,
  CASE
    WHEN hru.AvgPostScore > 50 THEN 'Highly Valued'
    WHEN hru.TotalEdits > 1000 THEN 'Prolific Editor'
    WHEN hru.CommentCount > 5000 THEN 'Community Contributor'
    ELSE 'Active User'
  END AS UserCategory,
  (
    SELECT
      COUNT(b.Id)
    FROM
      Badges AS b
    WHERE
      b.UserId = hru.Id AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(b.Id)
    FROM
      Badges AS b
    WHERE
      b.UserId = hru.Id AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(b.Id)
    FROM
      Badges AS b
    WHERE
      b.UserId = hru.Id AND b.Class = 3
  ) AS BronzeBadgeCount,
  COALESCE(hru.AvgPostScore, 0) + COALESCE(hru.TotalEdits, 0) * 0.1 + COALESCE(hru.TotalCommentScore, 0) * 0.01 AS PerformanceScore,
  UPPER(REPLACE(hru.DisplayName, ' ', '_')) AS FormattedDisplayName
FROM
  HighReputationUsers AS hru
WHERE
  hru.PostCount IS NOT NULL
  AND hru.AvgPostScore IS NOT NULL
  AND hru.TotalEdits IS NOT NULL
  AND hru.CommentCount IS NOT NULL
ORDER BY
  PerformanceScore DESC
LIMIT 100;