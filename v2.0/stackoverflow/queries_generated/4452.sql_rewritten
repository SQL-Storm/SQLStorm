-- {"query": "4452.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1032} 
WITH
  RankedPostHistory AS (
    SELECT
      PostId,
      PostHistoryTypeId,
      UserId,
      CreationDate,
      ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  RecentEdits AS (
    SELECT
      rph.PostId,
      p.OwnerUserId AS OriginalOwnerUserId,
      p.Title AS OriginalTitle,
      p.Tags AS OriginalTags,
      rph.UserId AS EditorUserId,
      u.DisplayName AS EditorDisplayName,
      rph.CreationDate AS EditDate,
      CASE
        WHEN rph.PostHistoryTypeId = 4 THEN 'Title Edit'
        WHEN rph.PostHistoryTypeId = 5 THEN 'Body Edit'
        WHEN rph.PostHistoryTypeId = 6 THEN 'Tags Edit'
        ELSE 'Unknown Edit Type'
      END AS EditType
    FROM RankedPostHistory AS rph
    JOIN Posts AS p
      ON rph.PostId = p.Id
    LEFT JOIN Users AS u
      ON rph.UserId = u.Id
    WHERE
      rph.rn = 1
  ),
  PostVoteCounts AS (
    SELECT
      PostId,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    WHERE
      VoteTypeId IN (2, 3)
    GROUP BY
      PostId
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  TopEditors AS (
    SELECT
      UserId,
      COUNT(*) AS EditCount
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      UserId
    ORDER BY
      EditCount DESC
    LIMIT 10
  )
SELECT
  re.PostId,
  re.OriginalOwnerUserId,
  re.OriginalTitle,
  re.OriginalTags,
  re.EditorUserId,
  re.EditorDisplayName,
  re.EditDate,
  re.EditType,
  COALESCE(pvc.UpVotes, 0) AS TotalUpVotes,
  COALESCE(pvc.DownVotes, 0) AS TotalDownVotes,
  COALESCE(upa.TotalPostsOwned, 0) AS UserTotalPostsOwned,
  COALESCE(upa.QuestionCount, 0) AS UserQuestionCount,
  COALESCE(upa.AnswerCount, 0) AS UserAnswerCount,
  upa.AvgScore,
  upa.LastPostDate,
  CASE
    WHEN te.UserId IS NOT NULL THEN 'Is Top 10 Editor'
    ELSE 'Not Top 10 Editor'
  END AS EditorStatus,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = re.PostId AND c.CreationDate > re.EditDate
  ) AS CommentsAfterEdit
FROM RecentEdits AS re
LEFT JOIN PostVoteCounts AS pvc
  ON re.PostId = pvc.PostId
LEFT JOIN UserPostActivity AS upa
  ON re.EditorUserId = upa.OwnerUserId
LEFT JOIN TopEditors AS te
  ON re.EditorUserId = te.UserId
WHERE
  re.EditDate > '2023-01-01'
  AND COALESCE(pvc.UpVotes, 0) > 10
  AND upa.AvgScore > 5
  AND re.OriginalTitle IS NOT NULL
  AND re.OriginalTitle <> ''
  AND re.EditorDisplayName IS NOT NULL
ORDER BY
  re.EditDate DESC,
  re.PostId
LIMIT 100;