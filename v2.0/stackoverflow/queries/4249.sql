WITH RankedPostEdits AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.CreationDate,
    ph.PostHistoryTypeId,
    ph.Text AS EditDetails,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  WHERE
    ph.PostHistoryTypeId IN (4, 5, 6)
),
UserEditsByPost AS (
  SELECT
    rpe.PostId,
    p.OwnerUserId,
    rpe.UserId AS EditorUserId,
    CASE
      WHEN p.OwnerUserId = rpe.UserId THEN 'Self Edit'
      ELSE 'External Edit'
    END AS EditType,
    rpe.CreationDate AS EditDate,
    p.Title,
    SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)) AS Tags,
    (
      SELECT COUNT(*)
      FROM Comments c
      WHERE c.PostId = rpe.PostId AND c.UserId = rpe.UserId
    ) AS UserCommentCount,
    (
      SELECT COUNT(DISTINCT ph2.UserId)
      FROM PostHistory ph2
      WHERE ph2.PostId = rpe.PostId
        AND ph2.CreationDate < rpe.CreationDate
        AND ph2.PostHistoryTypeId IN (4, 5, 6)
    ) AS PreviousEditorsCount
  FROM RankedPostEdits rpe
  JOIN Posts p
    ON rpe.PostId = p.Id
  WHERE
    rpe.rn = 1
),
PostMetrics AS (
  SELECT
    p.Id AS PostId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
    CAST((EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400) AS INTEGER) AS ActivityDays
  FROM Posts p
)
SELECT
  COALESCE(u.DisplayName, 'Unknown User') AS PostOwnerDisplayName,
  uebp.Title AS EditedPostTitle,
  uebp.Tags AS EditedPostTags,
  uebp.EditType,
  uebp.EditDate,
  pm.Score,
  pm.ViewCount,
  pm.AnswerCount,
  pm.CommentCount,
  pm.FavoriteCount,
  pm.IsClosed,
  pm.IsCommunityOwned,
  pm.ActivityDays,
  uebp.UserCommentCount,
  uebp.PreviousEditorsCount,
  pht.Name AS LastEditType
FROM UserEditsByPost uebp
LEFT JOIN Users u
  ON uebp.OwnerUserId = u.Id
JOIN PostMetrics pm
  ON uebp.PostId = pm.PostId
LEFT JOIN PostHistory ph_last_edit
  ON uebp.PostId = ph_last_edit.PostId AND uebp.EditDate = ph_last_edit.CreationDate
LEFT JOIN PostHistoryTypes pht
  ON ph_last_edit.PostHistoryTypeId = pht.Id

UNION ALL

SELECT
  COALESCE(u.DisplayName, 'Unknown User') AS PostOwnerDisplayName,
  uebp.Title AS EditedPostTitle,
  uebp.Tags AS EditedPostTags,
  uebp.EditType,
  uebp.EditDate,
  pm.Score,
  pm.ViewCount,
  pm.AnswerCount,
  pm.CommentCount,
  pm.FavoriteCount,
  pm.IsClosed,
  pm.IsCommunityOwned,
  pm.ActivityDays,
  uebp.UserCommentCount,
  uebp.PreviousEditorsCount,
  pht.Name AS LastEditType
FROM UserEditsByPost uebp
LEFT JOIN Users u
  ON uebp.OwnerUserId = u.Id
JOIN PostMetrics pm
  ON uebp.PostId = pm.PostId
LEFT JOIN PostHistory ph_last_edit
  ON uebp.PostId = ph_last_edit.PostId AND uebp.EditDate = ph_last_edit.CreationDate
LEFT JOIN PostHistoryTypes pht
  ON ph_last_edit.PostHistoryTypeId = pht.Id
WHERE
  uebp.EditDate < (
    SELECT MIN(ph_sub.CreationDate)
    FROM PostHistory ph_sub
    WHERE ph_sub.PostId = uebp.PostId AND ph_sub.PostHistoryTypeId IN (4, 5, 6)
  );