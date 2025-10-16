WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5)
  ),
  UserPostContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(p.AnswerCount) AS TotalAnswers,
      SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Posts p
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.OwnerUserId
  ),
  TopEditors AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS EditedPostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS EditedQuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS EditedAnswerCount
    FROM RankedPostEdits rpe
    JOIN Posts p
      ON rpe.PostId = p.Id
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
    HAVING
      COUNT(DISTINCT rpe.PostId) > 5
  ),
  UserReputationTrend AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.CreationDate DESC) AS rn,
      LAG(u.Reputation, 1, u.Reputation) OVER (PARTITION BY u.Id ORDER BY u.CreationDate) AS PreviousReputation
    FROM Users u
  )
SELECT
  COALESCE(upc.OwnerUserId, te.UserId) AS UserId,
  COALESCE(u.DisplayName, 'Deleted User') AS DisplayName,
  COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
  COALESCE(upc.TotalAnswers, 0) AS TotalAnswersPosted,
  COALESCE(upc.AcceptedAnswers, 0) AS AcceptedAnswers,
  COALESCE(te.EditedPostCount, 0) AS RecentEdits,
  COALESCE(te.EditedQuestionCount, 0) AS EditedQuestions,
  COALESCE(te.EditedAnswerCount, 0) AS EditedAnswers,
  COALESCE(urt.Reputation, 0) AS CurrentReputation,
  COALESCE(urt.Reputation - urt.PreviousReputation, 0) AS ReputationChange,
  CASE
    WHEN u.AccountId IS NULL THEN 'No Account ID'
    WHEN u.AccountId < 0 THEN 'Special Account'
    ELSE CAST(u.AccountId AS VARCHAR(20))
  END AS AccountIdentifier,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%gold%'
    ) THEN 'Has Gold Badge'
    ELSE 'No Gold Badge'
  END AS GoldBadgeStatus,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.ClosedDate IS NOT NULL
    ) THEN 'Has Closed Posts'
    ELSE 'No Closed Posts'
  END AS ClosedPostStatus,
  CASE
    WHEN LENGTH(TRIM(COALESCE(u.AboutMe, ''))) > 100 THEN 'Long About Me'
    ELSE 'Short About Me'
  END AS AboutMeLength,
  CASE
    WHEN u.Location IS NULL OR u.Location = '' THEN 'Unknown Location'
    WHEN u.Location LIKE '%Earth%' THEN 'Earth Resident'
    ELSE 'Other Location'
  END AS LocationCategory
FROM UserPostContribution upc
FULL OUTER JOIN TopEditors te
  ON upc.OwnerUserId = te.UserId
LEFT JOIN Users u
  ON COALESCE(upc.OwnerUserId, te.UserId) = u.Id
LEFT JOIN UserReputationTrend urt
  ON COALESCE(upc.OwnerUserId, te.UserId) = urt.UserId
WHERE
  urt.rn = 1
GROUP BY
  COALESCE(upc.OwnerUserId, te.UserId),
  u.DisplayName,
  upc.QuestionCount,
  upc.TotalAnswers,
  upc.AcceptedAnswers,
  te.EditedPostCount,
  te.EditedQuestionCount,
  te.EditedAnswerCount,
  urt.Reputation,
  urt.PreviousReputation,
  u.AccountId,
  u.Id,
  u.AboutMe,
  u.Location
ORDER BY
  CurrentReputation DESC,
  ReputationChange DESC,
  EditedPostCount DESC;