-- {"query": "4081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1180} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.RevisionGUID,
      ph.UserId,
      ph.UserDisplayName,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  MostRecentEdits AS (
    SELECT
      rpe.PostId,
      rpe.EditDate,
      rpe.UserId AS LastEditorUserId,
      rpe.UserDisplayName AS LastEditorDisplayName,
      rpe.PostHistoryTypeId,
      rpe.Comment AS LastEditComment
    FROM RankedPostEdits AS rpe
    WHERE
      rpe.rn = 1
  ),
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount,
      p.Tags,
      p.ClosedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS QuestionStatus,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AverageCommentScore,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      mre.LastEditorUserId,
      mre.LastEditorDisplayName,
      mre.EditDate AS LastEditDate,
      mre.LastEditComment
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN MostRecentEdits AS mre
      ON p.Id = mre.PostId
    WHERE
      p.PostTypeId = 1 -- Questions
    GROUP BY
      p.Id,
      p.Title,
      p.CreationDate,
      p.OwnerUserId,
      u.DisplayName,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount,
      p.Tags,
      p.ClosedDate,
      mre.LastEditorUserId,
      mre.LastEditorDisplayName,
      mre.EditDate,
      mre.LastEditComment
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  qd.QuestionCreationDate,
  qd.OwnerDisplayName AS QuestionOwner,
  qd.QuestionScore,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.ViewCount,
  qd.Tags,
  qd.QuestionStatus,
  qd.CommentCount,
  qd.AverageCommentScore,
  qd.UpVoteCount,
  qd.DownVoteCount,
  qd.LastEditorDisplayName,
  qd.LastEditDate,
  qd.LastEditComment,
  (
    SELECT
      COUNT(ph.Id)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = qd.QuestionId AND ph.PostHistoryTypeId = 10 -- Post Closed
  ) AS CloseEventCount,
  (
    SELECT
      STRING_AGG(pt.Name, ', ')
    FROM PostLinks AS pl
    JOIN LinkTypes AS lt
      ON pl.LinkTypeId = lt.Id
    JOIN PostTypes AS pt
      ON pl.RelatedPostId = pt.Id -- Just to have some join and filter
    WHERE
      pl.PostId = qd.QuestionId AND lt.Name = 'Duplicate'
  ) AS DuplicateLinks,
  CASE
    WHEN qd.LastEditDate IS NULL THEN 'No Edits'
    WHEN qd.LastEditDate > qd.QuestionCreationDate + INTERVAL '7 day' THEN 'Edited after 7 days'
    ELSE 'Edited within 7 days'
  END AS EditTimingCategory,
  COALESCE(qd.AverageCommentScore, 0) AS NonNullAverageCommentScore
FROM QuestionDetails AS qd
WHERE
  qd.QuestionScore > 10
  AND qd.AnswerCount > 0
  AND qd.FavoriteCount > 5
  AND qd.ViewCount > 1000
  AND qd.QuestionStatus = 'Open'
  AND qd.OwnerDisplayName IS NOT NULL
  AND qd.LastEditorDisplayName IS NOT NULL
  AND qd.QuestionTitle LIKE '%SQL%'
ORDER BY
  qd.QuestionScore DESC,
  qd.ViewCount DESC
LIMIT 100;
