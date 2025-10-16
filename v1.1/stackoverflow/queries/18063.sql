WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  RecentUserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      MAX(p.LastActivityDate) AS LastPostActivity
    FROM Users u
    JOIN Posts p
      ON u.Id = p.OwnerUserId
    WHERE
      u.Views > 1000
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  HighActivityQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.AnswerCount DESC) AS q_rank
    FROM Posts p
    WHERE
      p.PostTypeId = 1
      AND p.Score > 50
      AND p.AnswerCount > 10
      AND p.CreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-12-31'
  )
SELECT
  hsq.QuestionId,
  hsq.Title,
  hsq.Score,
  hsq.AnswerCount,
  hsq.FavoriteCount,
  u.DisplayName AS QuestionOwner,
  rua.DisplayName AS RecentActivityUser,
  rua.LastPostActivity,
  rpe.CreationDate AS LastEditDateByThisUser,
  CASE
    WHEN hsq.FavoriteCount > 100
    AND EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = hsq.QuestionId
        AND pl.LinkTypeId = 3
    ) THEN 'Highly Favorited and Linked'
    WHEN hsq.Score > 500 THEN 'Highly Scored'
    WHEN hsq.AnswerCount > 50 THEN 'Highly Answered'
    ELSE 'Standard High Activity'
  END AS QuestionCategory,
  COALESCE(pht.Name, 'Unknown Type') AS LastPostHistoryType,
  COUNT(c.Id) AS CommentCountOnQuestion
FROM HighActivityQuestions hsq
LEFT JOIN Users u
  ON hsq.OwnerUserId = u.Id
LEFT JOIN RankedPostEdits rpe
  ON hsq.QuestionId = rpe.PostId
  AND rpe.rn = 1
LEFT JOIN RecentUserActivity rua
  ON rpe.UserId = rua.UserId
LEFT JOIN PostHistoryTypes pht
  ON rpe.PostHistoryTypeId = pht.Id
LEFT JOIN Comments c
  ON hsq.QuestionId = c.PostId
WHERE
  hsq.q_rank <= 50
  AND (
    rpe.UserId IS NULL
    OR rpe.CreationDate > hsq.QuestionCreationDate + INTERVAL '30' DAY
  )
GROUP BY
  hsq.QuestionId,
  hsq.Title,
  hsq.Score,
  hsq.AnswerCount,
  hsq.FavoriteCount,
  u.DisplayName,
  rua.DisplayName,
  rua.LastPostActivity,
  rpe.CreationDate,
  CASE
    WHEN hsq.FavoriteCount > 100
    AND EXISTS (
      SELECT 1
      FROM PostLinks pl2
      WHERE pl2.PostId = hsq.QuestionId
        AND pl2.LinkTypeId = 3
    ) THEN 'Highly Favorited and Linked'
    WHEN hsq.Score > 500 THEN 'Highly Scored'
    WHEN hsq.AnswerCount > 50 THEN 'Highly Answered'
    ELSE 'Standard High Activity'
  END,
  pht.Name
HAVING
  COUNT(c.Id) > 5

UNION ALL

SELECT
  p.Id,
  p.Title,
  p.Score,
  p.AnswerCount,
  p.FavoriteCount,
  u.DisplayName,
  NULL,
  NULL,
  NULL,
  'Less Active Questions' AS QuestionCategory,
  'Initial Post' AS LastPostHistoryType,
  COUNT(c.Id)
FROM Posts p
JOIN Users u
  ON p.OwnerUserId = u.Id
LEFT JOIN Comments c
  ON p.Id = c.PostId
WHERE
  p.PostTypeId = 1
  AND p.Score BETWEEN 0 AND 10
  AND p.AnswerCount BETWEEN 0 AND 2
  AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY)
GROUP BY
  p.Id,
  p.Title,
  p.Score,
  p.AnswerCount,
  p.FavoriteCount,
  u.DisplayName
HAVING
  COUNT(c.Id) <= 2
ORDER BY
  QuestionCategory,
  Score DESC;