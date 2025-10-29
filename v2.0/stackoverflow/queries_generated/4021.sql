-- {"query": "4021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1371} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserContributionSummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
      SUM(COALESCE(p.Score, 0)) AS TotalScore,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  QuestionWithAcceptedAnswer AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      q.CreationDate AS QuestionCreationDate,
      q.OwnerUserId AS QuestionOwnerUserId,
      a.Id AS AcceptedAnswerId,
      a.OwnerUserId AS AcceptedAnswerOwnerUserId,
      a.CreationDate AS AcceptedAnswerCreationDate,
      DATEDIFF(minute, q.CreationDate, a.CreationDate) AS TimeToAcceptedAnswerMinutes
    FROM Posts q
    JOIN Posts a
      ON q.AcceptedAnswerId = a.Id
    WHERE
      q.PostTypeId = 1
      AND q.AcceptedAnswerId IS NOT NULL
  )
SELECT
  q.QuestionTitle,
  q.QuestionCreationDate,
  q.TimeToAcceptedAnswerMinutes,
  q.AcceptedAnswerCreationDate,
  qus.DisplayName AS QuestionOwnerDisplayName,
  qaa.DisplayName AS AcceptedAnswerOwnerDisplayName,
  qaa.TotalScore AS AcceptedAnswerOwnerTotalScore,
  qaa.BadgeCount AS AcceptedAnswerOwnerBadgeCount,
  -- Calculate the average score of other answers for this question
  (
    SELECT
      AVG(COALESCE(a2.Score, 0))
    FROM Posts a2
    WHERE
      a2.ParentId = q.QuestionId
      AND a2.Id <> q.AcceptedAnswerId
  ) AS AverageScoreOfOtherAnswers,
  -- Check if the question owner has received a badge for answering their own question (highly unlikely, but for complexity)
  CASE
    WHEN q.QuestionOwnerUserId = q.AcceptedAnswerOwnerUserId THEN 'OwnerAnsweredOwn'
    ELSE 'OwnerDidNotAnswer'
  END AS OwnerAnsweredOwnStatus,
  -- Get the latest edit date by the question owner and the accepted answer owner
  (
    SELECT
      rpe.EditDate
    FROM RankedPostEdits rpe
    WHERE
      rpe.PostId = q.QuestionId
      AND rpe.UserId = q.QuestionOwnerUserId
      AND rpe.rn = 1
  ) AS LatestQuestionEditDateByOwner,
  (
    SELECT
      rpe.EditDate
    FROM RankedPostEdits rpe
    WHERE
      rpe.PostId = q.AcceptedAnswerId
      AND rpe.UserId = q.AcceptedAnswerOwnerUserId
      AND rpe.rn = 1
  ) AS LatestAnswerEditDateByOwner,
  -- Count of answers from users with reputation > 1000 for this question
  (
    SELECT
      COUNT(a3.Id)
    FROM Posts a3
    JOIN Users u3
      ON a3.OwnerUserId = u3.Id
    WHERE
      a3.ParentId = q.QuestionId
      AND u3.Reputation > 1000
  ) AS HighReputationAnswerCount,
  -- Union of users who either asked the question or provided the accepted answer
  (
    SELECT
      COUNT(DISTINCT u4.Id)
    FROM Users u4
    WHERE
      u4.Id IN (q.QuestionOwnerUserId, q.AcceptedAnswerOwnerUserId)
  ) AS DistinctUsersInvolved,
  -- Check for any null values in key fields related to the accepted answer process
  CASE
    WHEN q.AcceptedAnswerId IS NULL
    OR q.AcceptedAnswerOwnerUserId IS NULL
    OR q.OwnerUserId IS NULL THEN 'IncompleteData'
    ELSE 'CompleteData'
  END AS DataCompletenessStatus
FROM QuestionWithAcceptedAnswer q
LEFT JOIN UserContributionSummary qus
  ON q.QuestionOwnerUserId = qus.UserId
LEFT JOIN UserContributionSummary qaa
  ON q.AcceptedAnswerOwnerUserId = qaa.UserId
WHERE
  q.TimeToAcceptedAnswerMinutes BETWEEN 1 AND 10000 -- Filter for reasonable time to answer
  AND q.QuestionOwnerUserId <> q.AcceptedAnswerOwnerUserId -- Exclude self-answered questions for this specific benchmark
  AND q.QuestionTitle NOT LIKE '%How do I%' -- Exclude simple "how-to" questions for diversity
  AND q.QuestionCreationDate >= DATEADD(year, -5, GETDATE()) -- Focus on recent activity
GROUP BY
  q.QuestionTitle,
  q.QuestionCreationDate,
  q.TimeToAcceptedAnswerMinutes,
  q.AcceptedAnswerCreationDate,
  qus.DisplayName,
  qaa.DisplayName,
  qaa.TotalScore,
  qaa.BadgeCount,
  q.QuestionOwnerUserId,
  q.AcceptedAnswerOwnerUserId
HAVING
  COUNT(DISTINCT q.QuestionId) > 5 -- Ensure sufficient data points for the group
ORDER BY
  q.TimeToAcceptedAnswerMinutes ASC,
  q.QuestionCreationDate DESC;
