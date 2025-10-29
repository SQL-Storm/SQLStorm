-- {"query": "4622.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1664} 

WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS Rank,
      LAG(p.OwnerUserId, 1, -1) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS PreviousAnswerOwnerId,
      SUM(CASE WHEN c.UserId IS NOT NULL AND c.CreationDate > p.CreationDate THEN 1 ELSE 0 END) AS CommentsAfterAnswer
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.Id,
      p.ParentId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score
  ),
  UserAnswerCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS TotalAnswersPosted,
      SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswers,
      AVG(Score) AS AverageAnswerScore
    FROM Posts
    WHERE
      PostTypeId = 2
    GROUP BY
      OwnerUserId
  ),
  QuestionEngagement AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId AS QuestionOwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
      COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS Favorites
    FROM Posts AS p
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount
  )
SELECT
  q.QuestionId,
  q.QuestionOwnerUserId,
  u.DisplayName AS QuestionOwnerDisplayName,
  q.QuestionCreationDate,
  q.QuestionScore,
  q.QuestionViewCount,
  q.AnswerCount,
  q.UpVotes AS QuestionUpVotes,
  q.DownVotes AS QuestionDownVotes,
  q.Favorites AS QuestionFavorites,
  ra1.PostId AS TopAnswerId,
  ra1.OwnerUserId AS TopAnswerOwnerId,
  u2.DisplayName AS TopAnswerOwnerDisplayName,
  ra1.AnswerCreationDate AS TopAnswerCreationDate,
  ra1.AnswerScore AS TopAnswerScore,
  ra1.CommentsAfterAnswer AS CommentsOnTopAnswer,
  ra2.PostId AS SecondAnswerId,
  ra2.OwnerUserId AS SecondAnswerOwnerId,
  u3.DisplayName AS SecondAnswerOwnerDisplayName,
  ra2.AnswerScore AS SecondAnswerScore,
  ra2.CommentsAfterAnswer AS CommentsOnSecondAnswer,
  CASE
    WHEN ra1.Rank = 1 AND ra1.OwnerUserId = q.QuestionOwnerUserId THEN 'AcceptedByQuestionOwner'
    WHEN ra1.Rank = 1 AND ra1.OwnerUserId = ra1.PreviousAnswerOwnerId THEN 'AcceptedFromPrevious'
    WHEN ra1.Rank = 1 THEN 'AcceptedByOthers'
    ELSE 'NoAcceptedAnswer'
  END AS AcceptanceStatus,
  COALESCE(uac.TotalAnswersPosted, 0) AS QuestionOwnerTotalAnswers,
  COALESCE(uac.PositiveScoreAnswers, 0) AS QuestionOwnerPositiveScoreAnswers,
  uac.AverageAnswerScore AS QuestionOwnerAverageAnswerScore,
  CASE
    WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN q.CreationDate < DATE('now', '-365 day') AND q.Score < 10 THEN 'OldAndLowScore'
    ELSE 'ActiveOrHighScore'
  END AS QuestionStatus,
  pht.Name AS LastPostHistoryAction,
  CASE
    WHEN pl.LinkTypeId = 3 THEN 'DuplicateLink'
    WHEN pl.LinkTypeId = 1 THEN 'LinkedPost'
    ELSE 'NoLink'
  END AS PostLinkType
FROM QuestionEngagement AS q
LEFT OUTER JOIN RankedAnswers AS ra1
  ON q.QuestionId = ra1.QuestionId AND ra1.Rank = 1
LEFT OUTER JOIN RankedAnswers AS ra2
  ON q.QuestionId = ra2.QuestionId AND ra2.Rank = 2
LEFT JOIN Users AS u
  ON q.QuestionOwnerUserId = u.Id
LEFT JOIN Users AS u2
  ON ra1.OwnerUserId = u2.Id
LEFT JOIN Users AS u3
  ON ra2.OwnerUserId = u3.Id
LEFT JOIN UserAnswerCounts AS uac
  ON q.QuestionOwnerUserId = uac.OwnerUserId
LEFT JOIN PostHistory AS ph
  ON q.QuestionId = ph.PostId AND ph.PostHistoryTypeId IN (4, 6) /* Edit Title, Edit Tags */
LEFT JOIN PostHistoryTypes AS pht
  ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN PostLinks AS pl
  ON q.QuestionId = pl.PostId AND pl.LinkTypeId = 3 /* Specifically for duplicate links */
WHERE
  q.QuestionScore > 5 AND q.AnswerCount > 0
UNION ALL
SELECT
  NULL AS QuestionId,
  NULL AS QuestionOwnerUserId,
  NULL AS QuestionOwnerDisplayName,
  NULL AS QuestionCreationDate,
  NULL AS QuestionScore,
  NULL AS QuestionViewCount,
  NULL AS AnswerCount,
  NULL AS QuestionUpVotes,
  NULL AS QuestionDownVotes,
  NULL AS QuestionFavorites,
  NULL AS TopAnswerId,
  NULL AS TopAnswerOwnerId,
  NULL AS TopAnswerOwnerDisplayName,
  NULL AS TopAnswerCreationDate,
  NULL AS TopAnswerScore,
  NULL AS CommentsOnTopAnswer,
  NULL AS SecondAnswerId,
  NULL AS SecondAnswerOwnerId,
  NULL AS SecondAnswerOwnerDisplayName,
  NULL AS SecondAnswerScore,
  NULL AS CommentsOnSecondAnswer,
  NULL AS AcceptanceStatus,
  NULL AS QuestionOwnerTotalAnswers,
  NULL AS QuestionOwnerPositiveScoreAnswers,
  NULL AS QuestionOwnerAverageAnswerScore,
  NULL AS QuestionStatus,
  NULL AS LastPostHistoryAction,
  NULL AS PostLinkType
FROM Users AS u
WHERE
  u.Reputation > 10000
  AND u.Id NOT IN (
    SELECT
      OwnerUserId
    FROM Posts
    WHERE
      PostTypeId = 1 AND OwnerUserId IS NOT NULL
  )
  AND u.Id NOT IN (
    SELECT
      UserId
    FROM Badges
    WHERE
      Name LIKE '%Expert%'
  );
