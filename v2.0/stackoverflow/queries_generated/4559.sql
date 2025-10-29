-- {"query": "4559.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1391} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      p.OwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
      JOIN Posts AS p ON ph.PostId = p.Id
    WHERE
      ph.PostHistoryTypeId IN (
        4,
        5,
        6
      ) /* Edit Title, Edit Body, Edit Tags */
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
      AVG(re.CreationDate::DATE - u.CreationDate::DATE) AS AvgDaysToFirstEdit
    FROM
      RankedPostEdits AS re
      JOIN Users AS u ON re.UserId = u.Id
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
      Posts AS p
      LEFT JOIN Posts AS a ON p.Id = a.ParentId AND a.PostTypeId = 2 /* Answers */
      LEFT JOIN Comments AS c ON p.Id = c.PostId
      LEFT JOIN PostTypes AS pt ON pt.Id = p.PostTypeId
    WHERE
      p.PostTypeId = 1 /* Questions */
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
  CONCAT(
    'Owner: ',
    u.DisplayName,
    ' (Rep: ',
    u.Reputation,
    ')'
  ) AS OwnerInfo,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = q.Id AND pl.LinkTypeId = 3 /* Duplicate */
    ) THEN 'Has Duplicates'
    ELSE 'No Known Duplicates'
  END AS DuplicateStatus,
  (
    SELECT
      COUNT(*)
    FROM
      Votes AS v
    WHERE
      v.PostId = q.Id AND v.VoteTypeId = 2 /* UpMod */
  ) AS UpVoteCount,
  (
    SELECT
      COUNT(*)
    FROM
      Votes AS v
    WHERE
      v.PostId = q.Id AND v.VoteTypeId = 3 /* DownMod */
  ) AS DownVoteCount,
  (
    SELECT
      AVG(CAST(v.CreationDate AS DATE) - CAST(q.CreationDate AS DATE))
    FROM
      Votes AS v
    WHERE
      v.PostId = q.Id AND v.VoteTypeId IN (2, 3)
  ) AS AvgVoteDaysSinceQuestionCreation,
  NULLIF(q.Tags, '') AS CleanedTags,
  REPLACE(REPLACE(q.Body, '<p>', ''), '</p>', '') AS BodyWithoutParagraphs,
  COALESCE(q.AnswerCount, 0) AS NonNullAnswerCount
FROM
  Posts AS q
  LEFT JOIN Users AS u ON q.OwnerUserId = u.Id
  LEFT JOIN PostEditCount AS pec ON q.Id = pec.PostId
  LEFT JOIN UserEditActivity AS uea ON u.Id = uea.UserId
  LEFT JOIN QuestionAnswerStats AS qas ON q.Id = qas.QuestionId
WHERE
  q.PostTypeId = 1 /* Questions */
  AND q.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND q.Score > 10
  AND u.Reputation > 5000
  AND COALESCE(q.FavoriteCount, 0) > 5
  AND q.OwnerUserId IS NOT NULL
  AND q.AcceptedAnswerId IS NOT NULL
  AND EXISTS (
    SELECT
      1
    FROM
      Comments AS c
    WHERE
      c.PostId = q.Id
      AND LENGTH(c.Text) > 50
  )
ORDER BY
  q.LastActivityDate DESC
LIMIT 100;
