WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS NextAnswerScore,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS PreviousAnswerScore,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.DisplayName AS OwnerDisplayName,
      (
        SELECT
          COUNT(*)
        FROM
          Comments c
        WHERE
          c.PostId = p.Id
      ) AS CommentCountOnAnswer,
      CASE
        WHEN p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1 THEN 1
        ELSE 0
      END AS IsOwnerValidUser,
      p.Score
    FROM
      Posts p
      INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
      INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      pt.Name = 'Answer'
      AND p.ParentId IS NOT NULL
  ),
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.OwnerUserId AS QuestionOwnerUserId,
      p.AcceptedAnswerId,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount AS QuestionAnswerCount,
      u.DisplayName AS QuestionOwnerDisplayName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      (
        SELECT
          COUNT(*)
        FROM
          PostLinks pl
        WHERE
          pl.PostId = p.Id
          AND pl.LinkTypeId = 3
      ) AS DuplicateLinkCount
    FROM
      Posts p
      INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      pt.Name = 'Question'
  )
SELECT
  qd.QuestionId,
  qd.Title AS QuestionTitle,
  qd.QuestionCreationDate,
  qd.QuestionOwnerDisplayName,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionAnswerCount,
  qd.IsClosed,
  qd.DuplicateLinkCount,
  ra.PostId AS BestAnswerId,
  ra.AnswerCreationDate AS BestAnswerCreationDate,
  ra.Reputation AS BestAnswererReputation,
  ra.UserCreationDate AS BestAnswererCreationDate,
  ra.OwnerDisplayName AS BestAnswererDisplayName,
  ra.CommentCountOnAnswer AS BestAnswerCommentCount,
  ra.IsOwnerValidUser AS IsBestAnswererValidUser,
  (ra.Score - ra.NextAnswerScore) AS ScoreDifferenceWithNextAnswer,
  (qd.QuestionScore * ra.Reputation) AS WeightedScore,
  CASE
    WHEN qd.AcceptedAnswerId = ra.PostId THEN 'Accepted'
    ELSE 'TopScoring'
  END AS AnswerSelectionMethod,
  CASE
    WHEN ra.AnswerCreationDate > qd.QuestionCreationDate + INTERVAL '1 day' THEN 'Delayed'
    ELSE 'Timely'
  END AS AnswerTimeliness,
  CONCAT(qd.QuestionOwnerDisplayName, ' - ', ra.OwnerDisplayName) AS UserPair,
  COALESCE(qd.Title, 'No Title') AS CoalescedTitle,
  CASE
    WHEN qd.QuestionOwnerUserId IS NULL THEN 'Anonymous'
    WHEN qd.QuestionOwnerUserId = -1 THEN 'Community'
    ELSE 'Registered'
  END AS QuestionOwnerType
FROM
  QuestionDetails qd
  LEFT JOIN RankedAnswers ra ON qd.QuestionId = ra.QuestionId
WHERE
  ra.RankByScore = 1
  AND qd.QuestionScore > 10
  AND ra.Reputation > 1000
  AND qd.QuestionAnswerCount > 2
  AND qd.IsClosed = 0
  AND ra.Score > 0
UNION ALL
SELECT
  qd.QuestionId,
  qd.Title AS QuestionTitle,
  qd.QuestionCreationDate,
  qd.QuestionOwnerDisplayName,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionAnswerCount,
  qd.IsClosed,
  qd.DuplicateLinkCount,
  NULL AS BestAnswerId,
  NULL AS BestAnswerCreationDate,
  NULL AS BestAnswererReputation,
  NULL AS BestAnswererCreationDate,
  NULL AS BestAnswererDisplayName,
  NULL AS BestAnswerCommentCount,
  NULL AS IsBestAnswererValidUser,
  NULL AS ScoreDifferenceWithNextAnswer,
  NULL AS WeightedScore,
  'NoAnswer' AS AnswerSelectionMethod,
  NULL AS AnswerTimeliness,
  qd.QuestionOwnerDisplayName AS UserPair,
  COALESCE(qd.Title, 'No Title') AS CoalescedTitle,
  CASE
    WHEN qd.QuestionOwnerUserId IS NULL THEN 'Anonymous'
    WHEN qd.QuestionOwnerUserId = -1 THEN 'Community'
    ELSE 'Registered'
  END AS QuestionOwnerType
FROM
  QuestionDetails qd
WHERE
  qd.QuestionAnswerCount = 0
  AND qd.QuestionScore > 5;