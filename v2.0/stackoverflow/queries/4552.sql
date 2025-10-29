-- {"query": "4552.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1019} 
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.UserDisplayName,
      ph.CreationDate AS EditDate,
      pht.Name AS EditType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
  ),
  RecentEditors AS (
    SELECT
      rpe.PostId,
      rpe.UserId,
      rpe.UserDisplayName,
      rpe.EditDate,
      rpe.EditType,
      rpe.rn
    FROM RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS PostCreationDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    WHERE
      p.PostTypeId = 1 /* Questions */
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.CreationDate
  ),
  UserPostContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserName,
      COUNT(DISTINCT p.Id) AS QuestionsAsked,
      SUM(p.AnswerCount) AS AnswersGiven,
      COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.Reputation > 10000
    GROUP BY
      u.Id,
      u.DisplayName
  )
SELECT
  pe.PostId,
  pe.Title,
  pe.PostCreationDate,
  upc.UserName AS OriginalPoster,
  upc.QuestionsAsked,
  upc.AnswersGiven,
  CASE
    WHEN pe.AcceptedAnswerCount > 0 THEN 'Has Accepted Answer'
    ELSE 'No Accepted Answer'
  END AS AcceptanceStatus,
  re.UserDisplayName AS LastEditor,
  re.EditDate AS LastEditDate,
  CASE
    WHEN re.EditType IS NULL THEN 'No Edits'
    WHEN re.EditType = 'Edit Title' THEN 'Title Edited'
    WHEN re.EditType = 'Edit Body' THEN 'Body Edited'
    WHEN re.EditType = 'Edit Tags' THEN 'Tags Edited'
    ELSE 'Other Edit'
  END AS LastEditDescription,
  COALESCE(pe.CommentCount, 0) AS TotalComments,
  COALESCE(pe.VoteCount, 0) AS TotalVotes,
  upc.BadgesEarned
FROM PostEngagement AS pe
LEFT JOIN Users AS u
  ON pe.OwnerUserId = u.Id
LEFT JOIN UserPostContribution AS upc
  ON u.Id = upc.UserId
LEFT JOIN RecentEditors AS re
  ON pe.PostId = re.PostId AND re.rn = 1
WHERE
  pe.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND (
    pe.VoteCount > 100
    OR pe.CommentCount > 50
  )
  AND (
    upc.BadgesEarned > 5 OR upc.QuestionsAsked > 20
  )
  AND u.Location IS NOT NULL
ORDER BY
  pe.PostCreationDate DESC,
  pe.VoteCount DESC
LIMIT 100;