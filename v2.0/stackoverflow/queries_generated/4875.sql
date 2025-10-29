-- {"query": "4875.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 981} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate AS EditDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AveragePostScore,
      MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  HighlyActiveUsers AS (
    SELECT
      UserId,
      DisplayName
    FROM Users
    WHERE
      Reputation > 10000
      AND (
        SELECT
          COUNT(*)
        FROM PostHistory AS ph
        WHERE
          ph.UserId = Users.Id
          AND ph.PostHistoryTypeId IN (4, 5, 6)
      ) > 50
  ),
  LatestEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS EditorUserId,
      rpe.EditDate,
      u.DisplayName AS EditorDisplayName
    FROM RankedPostEdits AS rpe
    JOIN Users AS u
      ON rpe.UserId = u.Id
    WHERE
      rpe.rn = 1
  ),
  PostCommentCounts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS PostCreationDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.CreationDate
  )
SELECT
  pu.DisplayName AS PostOwnerDisplayName,
  pca.Title AS PostTitle,
  pca.PostCreationDate,
  pca.CommentCount,
  pca.PositiveCommentCount,
  COALESCE(le.EditorDisplayName, 'N/A') AS LatestEditorDisplayName,
  le.EditDate AS LatestEditDate,
  hau.DisplayName AS HighlyActiveEditor,
  upa.TotalPostsOwned,
  upa.QuestionCount,
  upa.AnswerCount,
  upa.AveragePostScore,
  upa.LastPostActivityDate,
  CASE
    WHEN pcc.CommentCount > 10 AND upa.AnswerCount > 5 THEN 'High Engagement'
    WHEN pcc.PositiveCommentCount > 0 AND upa.AveragePostScore > 5 THEN 'Positive Feedback'
    WHEN le.EditDate > pca.PostCreationDate + INTERVAL '30 days' THEN 'Post-Launch Edit'
    WHEN upa.LastPostActivityDate < pca.PostCreationDate + INTERVAL '7 days' THEN 'Stale Post'
    ELSE 'Standard Activity'
  END AS ActivityStatus
FROM PostCommentCounts AS pcc
JOIN Users AS pu
  ON pcc.OwnerUserId = pu.Id
LEFT JOIN LatestEdits AS le
  ON pcc.PostId = le.PostId
LEFT JOIN UserPostActivity AS upa
  ON pcc.OwnerUserId = upa.OwnerUserId
LEFT JOIN HighlyActiveUsers AS hau
  ON le.EditorUserId = hau.UserId
WHERE
  pca.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND pcc.CommentCount > 0
  AND upa.TotalPostsOwned IS NOT NULL
ORDER BY
  pca.PostCreationDate DESC,
  pcc.CommentCount DESC;
