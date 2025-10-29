WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.Comment AS EditComment,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.Comment IS NOT NULL
  ),
  UserEditContribution AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS PostsEditedByThisUser,
      AVG(CASE WHEN rpe.EditType = 'Edit Title' THEN 1.0 ELSE 0.0 END) AS AvgTitleEditProportion,
      MAX(rpe.EditDate) AS LatestEditDate
    FROM RankedPostEdits rpe
    GROUP BY
      rpe.UserId
  ),
  PostEditImpact AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate,
      (
        SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id
      ) AS CommentCountActual,
      (
        SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id
      ) AS LinkCount,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      -- Standard SQL: compute days between dates using DATE_DIFF where available or simple date subtraction cast to integer days.
      -- Use ANSI SQL: (CAST(p.ClosedDate AS DATE) - CAST(p.CreationDate AS DATE))
      -- Some dialects return INTERVAL; extract epoch days when needed. Here use integer days via CAST subtraction.
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN CAST(p.ClosedDate AS DATE) - CAST(p.CreationDate AS DATE)
        ELSE NULL
      END AS DaysToClose
    FROM Posts p
    WHERE
      p.PostTypeId = 1
  )
SELECT
  pei.PostId,
  pei.Title,
  pei.Score,
  pei.AnswerCount,
  pei.CommentCount,
  pei.FavoriteCount,
  pei.ViewCount,
  pei.PostCreationDate,
  pei.LastActivityDate,
  pei.CommentCountActual,
  pei.LinkCount,
  pei.IsClosed,
  pei.DaysToClose,
  uec.PostsEditedByThisUser,
  uec.AvgTitleEditProportion,
  uec.LatestEditDate,
  CASE WHEN uec.UserId IS NULL THEN 'No Edits' ELSE 'Has Edits' END AS UserEditStatus,
  CASE
    WHEN pei.Score > 100 AND pei.AnswerCount > 5 AND pei.FavoriteCount > 10 THEN 'Highly Engaged Question'
    WHEN pei.Score < 0 AND pei.AnswerCount = 0 THEN 'Potentially Problematic Question'
    ELSE 'Standard Question'
  END AS QuestionEngagementCategory,
  UPPER(SUBSTRING(pei.Title FROM 1 FOR 3)) AS TitlePrefix,
  COALESCE(uec.PostsEditedByThisUser, 0) AS NormalizedEditCount
FROM PostEditImpact pei
LEFT JOIN UserEditContribution uec
  ON pei.OwnerUserId = uec.UserId
WHERE
  pei.Score > -5
  AND pei.AnswerCount <= 20
  AND pei.ViewCount > 100
  AND pei.PostCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  AND (uec.UserId IS NULL OR uec.PostsEditedByThisUser > 5)
ORDER BY
  pei.Score DESC,
  pei.AnswerCount DESC,
  pei.ViewCount DESC
LIMIT 100;