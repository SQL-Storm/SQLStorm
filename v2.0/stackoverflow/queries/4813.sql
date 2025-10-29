WITH QuestionCounts AS (
  SELECT
    OwnerUserId,
    COUNT(Id) AS NumQuestions
  FROM Posts
  WHERE PostTypeId = 1
  GROUP BY
    OwnerUserId
), AnswerCounts AS (
  SELECT
    OwnerUserId,
    COUNT(Id) AS NumAnswers
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY
    OwnerUserId
), UserActivity AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(qc.NumQuestions, 0) AS TotalQuestions,
    COALESCE(ac.NumAnswers, 0) AS TotalAnswers,
    (
      SELECT
        COUNT(*)
      FROM Comments c
      WHERE
        c.UserId = u.Id
    ) AS TotalComments,
    (
      SELECT
        COUNT(*)
      FROM Votes v
      WHERE
        v.UserId = u.Id AND v.VoteTypeId IN (2, 3)
    ) AS TotalVotesCast,
    (
      SELECT
        COUNT(*)
      FROM Badges b
      WHERE
        b.UserId = u.Id
    ) AS TotalBadges,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN 1 ELSE 0 END), 0) AS TotalEdits,
    AVG(p.Score) AS AvgPostScore,
    u.CreationDate
  FROM Users u
  LEFT JOIN QuestionCounts qc
    ON u.Id = qc.OwnerUserId
  LEFT JOIN AnswerCounts ac
    ON u.Id = ac.OwnerUserId
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  LEFT JOIN PostHistory ph
    ON u.Id = ph.UserId
  GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    qc.NumQuestions,
    ac.NumAnswers,
    u.CreationDate
), RankedUserActivity AS (
  SELECT
    ua.Id,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalComments,
    ua.TotalVotesCast,
    ua.TotalBadges,
    ua.TotalEdits,
    ua.AvgPostScore,
    ua.CreationDate,
    ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.TotalQuestions DESC) AS ReputationRank,
    SUM(ua.TotalEdits) OVER (ORDER BY ua.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalEdits
  FROM UserActivity ua
)
SELECT
  rua.DisplayName,
  rua.Reputation,
  rua.TotalQuestions,
  rua.TotalAnswers,
  rua.TotalComments,
  rua.TotalVotesCast,
  rua.TotalBadges,
  rua.TotalEdits,
  rua.AvgPostScore,
  rua.ReputationRank,
  rua.RunningTotalEdits,
  CASE
    WHEN rua.Reputation > 10000 THEN 'High Reputation'
    WHEN rua.Reputation BETWEEN 1000 AND 10000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS ReputationTier,
  CASE
    WHEN rua.TotalQuestions > 50 OR rua.TotalAnswers > 100 THEN 'Active Contributor'
    WHEN rua.TotalEdits > 20 THEN 'Frequent Editor'
    ELSE 'Occasional Contributor'
  END AS ContributionLevel,
  CASE
    WHEN UPPER(rua.DisplayName) LIKE '%JOHN%' THEN 'Contains "John"'
    WHEN LOWER(rua.DisplayName) LIKE '%smith%' THEN 'Contains "Smith"'
    ELSE 'No common name pattern'
  END AS NamePattern,
  CASE
    WHEN COALESCE(rua.TotalQuestions, 0) + COALESCE(rua.TotalAnswers, 0) = 0 THEN 'No posts'
    WHEN COALESCE(rua.TotalQuestions, 0) > COALESCE(rua.TotalAnswers, 0) THEN 'More Questions than Answers'
    WHEN COALESCE(rua.TotalAnswers, 0) > COALESCE(rua.TotalQuestions, 0) THEN 'More Answers than Questions'
    ELSE 'Equal Questions and Answers'
  END AS PostBalance
FROM RankedUserActivity rua
WHERE
  rua.Reputation > 100
  AND COALESCE(rua.TotalQuestions,0) + COALESCE(rua.TotalAnswers,0) > 10
  AND (
    rua.DisplayName IS NOT NULL
    AND LENGTH(rua.DisplayName) > 3
  )
  AND EXISTS (
    SELECT
      1
    FROM Posts p
    WHERE
      p.OwnerUserId = rua.Id AND p.ClosedDate IS NOT NULL
  )
UNION
SELECT
  'Community User' AS DisplayName,
  NULL AS Reputation,
  NULL AS TotalQuestions,
  NULL AS TotalAnswers,
  NULL AS TotalComments,
  NULL AS TotalVotesCast,
  NULL AS TotalBadges,
  NULL AS TotalEdits,
  NULL AS AvgPostScore,
  NULL AS ReputationRank,
  NULL AS RunningTotalEdits,
  'System' AS ReputationTier,
  'System' AS ContributionLevel,
  'System' AS NamePattern,
  'System' AS PostBalance
WHERE
  1 = 1;