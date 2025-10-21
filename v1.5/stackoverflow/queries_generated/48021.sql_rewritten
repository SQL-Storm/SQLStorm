-- {"query": "48021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 654} 
WITH RankedPostEdits AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
  FROM PostHistory ph
  WHERE
    ph.PostHistoryTypeId IN (4, 5, 6)
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPostsCreated,
    COUNT(DISTINCT ph.PostId) AS TotalEdits,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
    SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
    MAX(u.CreationDate) AS LastUserCreationDate,
    MAX(p.CreationDate) AS LastPostCreationDate,
    MAX(ph.CreationDate) AS LastEditDate
  FROM Users u
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  LEFT JOIN RankedPostEdits rpe
    ON u.Id = rpe.UserId
  LEFT JOIN PostHistory ph
    ON rpe.PostId = ph.PostId AND rpe.UserId = ph.UserId AND rpe.PostHistoryTypeId = ph.PostHistoryTypeId AND rpe.CreationDate = ph.CreationDate
  WHERE
    u.Id <> -1
  GROUP BY
    u.Id,
    u.DisplayName
)
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.TotalPostsCreated,
  ua.TotalEdits,
  ua.TitleEdits,
  ua.BodyEdits,
  ua.TagEdits,
  ua.LastUserCreationDate,
  ua.LastPostCreationDate,
  ua.LastEditDate,
  CASE
    WHEN ua.TotalEdits > 0 THEN CAST(ua.TotalEdits AS REAL) / ua.TotalPostsCreated
    ELSE 0
  END AS EditRatio,
  CASE
    WHEN ua.BodyEdits > 0 THEN CAST(ua.BodyEdits AS REAL) / ua.TotalEdits
    ELSE 0
  END AS BodyEditProportion,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = ua.UserId AND b.Name LIKE '%Editor%'
  ) AS EditorBadgeCount
FROM UserActivity ua
ORDER BY
  ua.TotalEdits DESC,
  ua.LastEditDate DESC
LIMIT 1000;