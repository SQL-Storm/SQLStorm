-- {"query": "4851.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1383} 

WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswererUserId,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByScore,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS PreviousScore
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2
  ),
  UserAnswerStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(ra.PostId) AS TotalAnswers,
      SUM(CASE WHEN ra.RankByScore = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers,
      AVG(ra.Score) AS AverageAnswerScore,
      MAX(u.Reputation) AS MaxReputation,
      MIN(u.CreationDate) AS UserCreationDate,
      COUNT(DISTINCT ph.PostId) AS EditedPostsCount
    FROM Users AS u
    LEFT JOIN RankedAnswers AS ra
      ON u.Id = ra.AnswererUserId
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (5, 8) -- Edits and Rollbacks
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.OwnerUserId AS QuestionerUserId,
      q.AcceptedAnswerId,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.AnswerCount,
      q.Tags,
      pt.Name AS PostTypeName,
      COALESCE(u.DisplayName, 'Deleted User') AS QuestionerDisplayName,
      CASE WHEN q.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus
    FROM Posts AS q
    JOIN PostTypes AS pt
      ON q.PostTypeId = pt.Id
    LEFT JOIN Users AS u
      ON q.OwnerUserId = u.Id
    WHERE
      q.PostTypeId = 1
  ),
  HighReputationUsers AS (
    SELECT
      UserId,
      DisplayName,
      Reputation,
      UserCreationDate
    FROM UserAnswerStats
    WHERE
      Reputation > 10000
  )
SELECT
  qd.QuestionId,
  qd.Title AS QuestionTitle,
  qd.QuestionerDisplayName,
  qd.QuestionCreationDate,
  qd.QuestionStatus,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.Tags,
  COALESCE(ra.TotalAnswers, 0) AS TotalAnswersForQuestion,
  COALESCE(ra.AcceptedAnswers, 0) AS AcceptedAnswersForQuestion,
  COALESCE(ra.AverageAnswerScore, 0.0) AS AverageAnswerScoreForQuestion,
  uhr.DisplayName AS HighReputationAnswerer,
  uhr.Reputation AS HighReputationAnswererReputation,
  COUNT(c.Id) AS CommentCountOnQuestion,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = qd.QuestionId AND pl.LinkTypeId = 3
  ) AS DuplicateLinks,
  CASE
    WHEN qd.AcceptedAnswerId IS NOT NULL
    AND EXISTS (
      SELECT
        1
      FROM Comments AS c_qa
      WHERE
        c_qa.PostId = qd.AcceptedAnswerId AND LENGTH(c_qa.Text) > 200
    )
    THEN 'Long Comment on Accepted Answer'
    ELSE 'No Long Comment on Accepted Answer'
  END AS LongCommentOnAcceptedAnswer,
  CASE
    WHEN qd.QuestionScore < 0
    AND qd.AnswerCount > 5 THEN 'Low Score, High Answer Count'
    WHEN qd.QuestionScore > 50
    AND qd.ViewCount > 5000 THEN 'High Score, High View Count'
    ELSE 'Moderate Activity'
  END AS QuestionActivityLevel,
  FORMAT(qd.QuestionCreationDate, 'yyyy-MM') AS QuestionMonth,
  ud.EditedPostsCount AS AnswererEditedPostCount
FROM QuestionDetails AS qd
LEFT JOIN (
  SELECT
    QuestionId,
    COUNT(PostId) AS TotalAnswers,
    SUM(CASE WHEN RankByScore = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers,
    AVG(Score) AS AverageAnswerScore
  FROM RankedAnswers
  GROUP BY
    QuestionId
) AS ra
  ON qd.QuestionId = ra.QuestionId
LEFT JOIN Users AS u_answerer
  ON qd.OwnerUserId = u_answerer.Id
LEFT JOIN UserAnswerStats AS ud
  ON qd.OwnerUserId = ud.UserId
LEFT JOIN HighReputationUsers AS uhr
  ON qd.OwnerUserId = uhr.UserId -- Joining to HighReputationUsers to see if the questioner is also a high rep user
LEFT JOIN Comments AS c
  ON qd.QuestionId = c.PostId
GROUP BY
  qd.QuestionId,
  qd.Title,
  qd.QuestionerDisplayName,
  qd.QuestionCreationDate,
  qd.QuestionStatus,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.Tags,
  ra.TotalAnswers,
  ra.AcceptedAnswers,
  ra.AverageAnswerScore,
  uhr.DisplayName,
  uhr.Reputation,
  ud.EditedPostsCount
HAVING
  COUNT(c.Id) > 10 OR ra.AverageAnswerScore > 5.0 OR qd.QuestionScore > 100
ORDER BY
  qd.QuestionCreationDate DESC,
  qd.QuestionScore DESC
LIMIT 100;
