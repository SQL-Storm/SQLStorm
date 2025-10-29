-- {"query": "4714.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 829} 
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
      MAX(p.CreationDate) AS LatestPostDate
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  TopEdits AS (
    SELECT
      re.UserId,
      COUNT(*) AS EditCount,
      SUM(CASE WHEN re.PostHistoryTypeId IN (4, 6) THEN 1 ELSE 0 END) AS TitleTagEdits,
      SUM(CASE WHEN re.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits
    FROM RankedPostEdits AS re
    WHERE
      re.rn = 1
    GROUP BY
      re.UserId
    HAVING
      COUNT(*) > 5
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
      SELECT
        1
      FROM Badges AS b
      WHERE
        b.UserId = u.Id AND b.Name = 'Editor'
    ) THEN 'Has Editor Badge'
    ELSE 'No Editor Badge'
  END AS EditorBadgeStatus
FROM Users AS u
LEFT JOIN UserPostActivity AS upa
  ON u.Id = upa.OwnerUserId
LEFT JOIN TopEdits AS te
  ON u.Id = te.UserId
LEFT JOIN PostHistory AS ph_latest
  ON u.Id = ph_latest.UserId
LEFT JOIN PostHistoryTypes AS pht
  ON ph_latest.PostHistoryTypeId = pht.Id
LEFT JOIN Posts AS p
  ON ph_latest.PostId = p.Id AND ph_latest.rn = 1
WHERE
  u.Reputation > 1000
  AND u.Views > 5000
  AND upa.TotalPostsOwned IS NOT NULL
  AND te.UserId IS NOT NULL
  AND ph_latest.PostHistoryTypeId IN (4, 5, 6)
  AND ph_latest.CreationDate = (
    SELECT
      MAX(ph2.CreationDate)
    FROM PostHistory AS ph2
    WHERE
      ph2.UserId = u.Id AND ph2.PostHistoryTypeId IN (4, 5, 6)
  )
ORDER BY
  u.Reputation DESC,
  te.EditCount DESC;