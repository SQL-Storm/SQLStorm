WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserEditFrequency AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS DistinctPostsEdited,
      AVG(EXTRACT(EPOCH FROM (CAST(rpe.EditDate AS timestamp) - CAST(p.CreationDate AS timestamp)))) AS AvgTimeToFirstEditSeconds,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits
    FROM RankedPostEdits AS rpe
    JOIN Posts AS p
      ON rpe.PostId = p.Id
    WHERE
      rpe.rn = 1
    GROUP BY
      rpe.UserId
  ),
  HighReputationUsers AS (
    SELECT
      Id
    FROM Users
    WHERE
      Reputation > 100000
  ),
  FrequentVoters AS (
    SELECT
      UserId,
      COUNT(*) AS TotalVotes,
      COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS Upvotes,
      COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS Downvotes,
      AVG(EXTRACT(EPOCH FROM CAST(CreationDate AS timestamp))) AS AvgVoteTimestamp
    FROM Votes
    WHERE
      VoteTypeId IN (2, 3)
    GROUP BY
      UserId
    HAVING
      COUNT(*) > 5000
  )
SELECT
  u.DisplayName,
  u.Reputation,
  COALESCE(uef.DistinctPostsEdited, 0) AS UserDistinctPostsEdited,
  COALESCE(uef.TitleEdits, 0) AS UserTitleEdits,
  COALESCE(uef.BodyEdits, 0) AS UserBodyEdits,
  COALESCE(uef.TagEdits, 0) AS UserTagEdits,
  COALESCE(fv.TotalVotes, 0) AS FrequentVoterTotalVotes,
  COALESCE(fv.Upvotes, 0) AS FrequentVoterUpvotes,
  COALESCE(fv.Downvotes, 0) AS FrequentVoterDownvotes,
  CASE
    WHEN hr.Id IS NOT NULL THEN 'High Reputation'
    ELSE 'Standard Reputation'
  END AS ReputationTier,
  CASE
    WHEN fv.UserId IS NOT NULL AND fv.AvgVoteTimestamp BETWEEN EXTRACT(EPOCH FROM TIMESTAMP '2023-01-01 00:00:00') AND EXTRACT(EPOCH FROM TIMESTAMP '2023-12-31 23:59:59') THEN 'Voted in 2023'
    WHEN fv.UserId IS NOT NULL THEN 'Voted in other periods'
    ELSE 'Infrequent Voter'
  END AS VoterActivityPeriod,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = u.Id AND b.Name LIKE '%Editor%'
  ) AS EditorBadgeCount,
  (
    SELECT
      SUM(p.AnswerCount)
    FROM Posts AS p
    WHERE
      p.OwnerUserId = u.Id AND p.PostTypeId = 1
  ) AS TotalAnswersOnOwnedQuestions
FROM Users AS u
LEFT JOIN UserEditFrequency AS uef
  ON u.Id = uef.UserId
LEFT JOIN FrequentVoters AS fv
  ON u.Id = fv.UserId
LEFT JOIN HighReputationUsers AS hr
  ON u.Id = hr.Id
WHERE
  u.DisplayName IS NOT NULL AND LENGTH(u.DisplayName) > 3
  AND (
    fv.UserId IS NOT NULL OR hr.Id IS NOT NULL
  )
GROUP BY
  u.DisplayName,
  u.Reputation,
  u.Id,
  uef.DistinctPostsEdited,
  uef.TitleEdits,
  uef.BodyEdits,
  uef.TagEdits,
  fv.UserId,
  fv.TotalVotes,
  fv.Upvotes,
  fv.Downvotes,
  fv.AvgVoteTimestamp,
  hr.Id
ORDER BY
  u.Reputation DESC,
  UserDistinctPostsEdited DESC
LIMIT 100;