WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      p.OwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
      JOIN Posts p ON ph.PostId = p.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  PostEditCount AS (
    SELECT
      PostId,
      COUNT(*) AS EditCount
    FROM
      RankedPostEdits
    GROUP BY
      PostId
  ),
  UserEditActivity AS (
    SELECT
      re.UserId,
      COUNT(DISTINCT re.PostId) AS DistinctPostsEdited,
      SUM(CASE WHEN re.rn = 1 THEN 1 ELSE 0 END) AS FirstEdits,
      AVG(EXTRACT(EPOCH FROM (re.CreationDate - u.CreationDate)) / 86400.0) AS AvgDaysToFirstEdit
    FROM
      RankedPostEdits re
      JOIN Users u ON re.UserId = u.Id
    WHERE
      re.rn = 1
    GROUP BY
      re.UserId
  ),
  QuestionAnswerStats AS (
    SELECT
      p.Id AS QuestionId,
      COUNT(DISTINCT a.Id) AS AnswerCount,
      SUM(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS AcceptedAnswerProvided,
      AVG(a.Score) AS AvgAnswerScore,
      MAX(a.Score) AS MaxAnswerScore,
      COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
      SUM(CASE WHEN c.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS OwnerCommentsOnQuestion,
      STRING_AGG(DISTINCT pt.Name, ', ') AS PostTypesInThread
    FROM
      Posts p
      LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
      LEFT JOIN Comments c ON p.Id = c.PostId
      LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id
  )
SELECT
  q.Id AS QuestionId,
  q.Title,
  q.CreationDate AS QuestionCreationDate,
  u.DisplayName AS OwnerDisplayName,
  qas.AnswerCount,
  qas.AcceptedAnswerProvided,
  qas.AvgAnswerScore,
  qas.MaxAnswerScore,
  qas.CommentCountOnQuestion,
  qas.OwnerCommentsOnQuestion,
  pec.EditCount AS TotalPostEdits,
  COALESCE(uea.DistinctPostsEdited, 0) AS UserDistinctPostsEdited,
  COALESCE(uea.FirstEdits, 0) AS UserFirstEdits,
  uea.AvgDaysToFirstEdit,
  CASE
    WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN q.FavoriteCount > 1000 THEN 'Highly Favorited'
    WHEN q.ViewCount > 100000 THEN 'Highly Viewed'
    ELSE 'Standard'
  END AS QuestionStatus,
  ('Owner: ' || u.DisplayName || ' (Rep: ' || CAST(u.Reputation AS VARCHAR) || ')') AS OwnerInfo,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicates'
    ELSE 'No Known Duplicates'
  END AS DuplicateStatus,
  (
    SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2
  ) AS UpVoteCount,
  (
    SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3
  ) AS DownVoteCount,
  (
    SELECT AVG(EXTRACT(EPOCH FROM (v.CreationDate - q.CreationDate)) / 86400.0)
    FROM Votes v
    WHERE v.PostId = q.Id AND v.VoteTypeId IN (2, 3)
  ) AS AvgVoteDaysSinceQuestionCreation,
  NULLIF(q.Tags, '') AS CleanedTags,
  REPLACE(REPLACE(q.Body, '<p>', ''), '</p>', '') AS BodyWithoutParagraphs,
  COALESCE(q.AnswerCount, 0) AS NonNullAnswerCount
FROM
  Posts q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN PostEditCount pec ON q.Id = pec.PostId
  LEFT JOIN UserEditActivity uea ON u.Id = uea.UserId
  LEFT JOIN QuestionAnswerStats qas ON q.Id = qas.QuestionId
WHERE
  q.PostTypeId = 1
  AND q.CreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-12-31'
  AND q.Score > 10
  AND u.Reputation > 5000
  AND COALESCE(q.FavoriteCount, 0) > 5
  AND q.OwnerUserId IS NOT NULL
  AND q.AcceptedAnswerId IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM Comments c WHERE c.PostId = q.Id AND LENGTH(c.Text) > 50
  )
ORDER BY
  q.LastActivityDate DESC
LIMIT 100;