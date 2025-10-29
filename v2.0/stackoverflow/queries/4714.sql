WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
      MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
  ),
  TopEdits AS (
    SELECT
      re.UserId,
      COUNT(*) AS EditCount,
      SUM(CASE WHEN re.PostHistoryTypeId IN (4, 6) THEN 1 ELSE 0 END) AS TitleTagEdits,
      SUM(CASE WHEN re.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits
    FROM RankedPostEdits re
    WHERE re.rn = 1
    GROUP BY re.UserId
    HAVING COUNT(*) > 5
  )
SELECT
  u.DisplayName,
  u.Reputation,
  upa.TotalPostsOwned,
  upa.QuestionsOwned,
  upa.AnswersOwned,
  te.EditCount,
  te.TitleTagEdits,
  te.BodyEdits,
  COALESCE(pht.Name, 'No Edits') AS LatestEditType,
  p.Title AS LatestEditedPostTitle,
  CASE
    WHEN u.LastAccessDate > upa.LatestPostDate THEN 'Inactive User'
    WHEN u.LastAccessDate IS NULL THEN 'Never Accessed'
    ELSE 'Active User'
  END AS UserStatus,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = u.Id AND b.Name = 'Editor'
    ) THEN 'Has Editor Badge'
    ELSE 'No Editor Badge'
  END AS EditorBadgeStatus
FROM Users u
LEFT JOIN UserPostActivity upa
  ON u.Id = upa.OwnerUserId
LEFT JOIN TopEdits te
  ON u.Id = te.UserId
LEFT JOIN (
  SELECT rpe.*
  FROM RankedPostEdits rpe
  WHERE rpe.rn = 1
) ph_latest
  ON u.Id = ph_latest.UserId
LEFT JOIN PostHistoryTypes pht
  ON ph_latest.PostHistoryTypeId = pht.Id
LEFT JOIN Posts p
  ON ph_latest.PostId = p.Id
WHERE
  u.Reputation > 1000
  AND u.Views > 5000
  AND upa.TotalPostsOwned IS NOT NULL
  AND te.UserId IS NOT NULL
  AND ph_latest.PostHistoryTypeId IN (4, 5, 6)
  AND ph_latest.CreationDate = (
    SELECT MAX(ph2.CreationDate)
    FROM PostHistory ph2
    WHERE ph2.UserId = u.Id AND ph2.PostHistoryTypeId IN (4, 5, 6)
  )
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.LastAccessDate,
  u.Views,
  upa.TotalPostsOwned,
  upa.QuestionsOwned,
  upa.AnswersOwned,
  upa.LatestPostDate,
  te.UserId,
  te.EditCount,
  te.TitleTagEdits,
  te.BodyEdits,
  pht.Name,
  p.Title
ORDER BY
  u.Reputation DESC,
  te.EditCount DESC;