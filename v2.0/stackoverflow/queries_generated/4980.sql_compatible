WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.UserId IS NOT NULL
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      (
        SELECT
          COUNT(DISTINCT b.Id)
        FROM Badges b
        WHERE
          b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadgeCount
    FROM Users u
    LEFT JOIN Comments c
      ON u.Id = c.UserId
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostPerformance AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.CreationDate,
      p.OwnerUserId,
      pt.Name AS PostTypeName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
      END AS PostStatus,
      COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
      COALESCE(p.Score * 100.0 / NULLIF(p.ViewCount, 0), 0) AS ScorePerViewRatio,
      COALESCE(p.AnswerCount * 100.0 / NULLIF(p.CommentCount, 0), 0) AS AnswerToCommentRatio
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId IN (1, 2)
      AND p.OwnerUserId IS NOT NULL
  )
SELECT
  ue.UserId,
  ue.DisplayName,
  ue.Reputation,
  ue.GoldBadgeCount,
  pp.PostId,
  pp.Title,
  pp.PostTypeName,
  pp.PostStatus,
  pp.Score,
  pp.ViewCount,
  pp.FavoriteCount,
  pp.ScorePerViewRatio,
  pp.AnswerToCommentRatio,
  rpe.CreationDate AS LastEditDate,
  ue.CommentCount,
  ue.PostCount,
  ue.QuestionCount,
  ue.AnswerCount,
  CASE
    WHEN ue.Reputation > 100000 THEN 'High'
    WHEN ue.Reputation BETWEEN 10000 AND 100000 THEN 'Medium'
    ELSE 'Low'
  END AS ReputationTier,
  CASE
    WHEN pp.Score > 500 THEN 'High Score'
    WHEN pp.Score BETWEEN 50 AND 500 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreTier,
  CASE
    WHEN pp.ViewCount > 1000000 THEN 'Very High Views'
    WHEN pp.ViewCount > 100000 THEN 'High Views'
    ELSE 'Moderate Views'
  END AS ViewCountTier
FROM UserEngagement ue
JOIN PostPerformance pp
  ON ue.UserId = pp.OwnerUserId
LEFT JOIN RankedPostEdits rpe
  ON ue.UserId = rpe.UserId
  AND pp.PostId = rpe.PostId
  AND rpe.rn = 1
WHERE
  pp.Score > 0
  AND pp.ViewCount > 0
  AND pp.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days')
ORDER BY
  ue.Reputation DESC,
  pp.Score DESC,
  pp.ViewCount DESC,
  pp.ScorePerViewRatio DESC
LIMIT 100;