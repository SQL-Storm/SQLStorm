WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostInteractions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      (
        SELECT COUNT(c.Id)
        FROM Comments c
        WHERE c.PostId = p.Id AND c.UserId IS NOT NULL
      ) AS CommentCountOnPost,
      (
        SELECT COUNT(v.Id)
        FROM Votes v
        WHERE v.PostId = p.Id AND v.VoteTypeId = 2
      ) AS UpVoteCountOnPost,
      p.AnswerCount,
      p.FavoriteCount,
      COALESCE(u.Reputation, 0) AS OwnerReputation,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      u.DisplayName AS OwnerDisplayName
    FROM
      Posts p
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
  ),
  PostEditSummary AS (
    SELECT
      rpe.PostId,
      COUNT(DISTINCT rpe.UserId) AS NumberOfUniqueEditors,
      MAX(rpe.CreationDate) AS LastEditDate,
      EXTRACT(EPOCH FROM (MAX(rpe.CreationDate) - MIN(rpe.CreationDate))) / 60.0 AS TimeBetweenFirstAndLastEditMinutes
    FROM
      RankedPostEdits rpe
    GROUP BY
      rpe.PostId
  ),
  TopContributors AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(p.Id) AS QuestionsAnswered,
      SUM(p.Score) AS TotalScoreReceived,
      ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC, SUM(p.Score) DESC) AS ContributorRank
    FROM
      Users u
      JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
      p.PostTypeId = 2
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 months')
    GROUP BY
      u.Id,
      u.DisplayName
    HAVING
      COUNT(p.Id) > 5
  )
SELECT
  upi.PostId,
  upi.OwnerDisplayName,
  upi.OwnerReputation,
  upi.PostCreationDate,
  upi.CommentCountOnPost,
  upi.UpVoteCountOnPost,
  upi.AnswerCount,
  upi.FavoriteCount,
  upi.IsClosed,
  COALESCE(pes.NumberOfUniqueEditors, 0) AS NumberOfUniqueEditors,
  pes.TimeBetweenFirstAndLastEditMinutes,
  CASE
    WHEN pes.LastEditDate IS NULL THEN 'Never Edited'
    WHEN EXTRACT(EPOCH FROM (pes.LastEditDate - upi.PostCreationDate)) < 3600 * 24 THEN 'Within 24 Hours'
    WHEN EXTRACT(EPOCH FROM (pes.LastEditDate - upi.PostCreationDate)) < 3600 * 24 * 7 THEN 'Within 7 Days'
    ELSE 'More Than 7 Days'
  END AS EditWindow,
  COALESCE(tc.QuestionsAnswered, 0) AS TopContributorAnswers,
  COALESCE(tc.TotalScoreReceived, 0) AS TopContributorScore,
  CASE
    WHEN upi.OwnerReputation BETWEEN 0 AND 99 THEN 'New User'
    WHEN upi.OwnerReputation BETWEEN 100 AND 999 THEN 'Beginner'
    WHEN upi.OwnerReputation BETWEEN 1000 AND 9999 THEN 'Intermediate'
    WHEN upi.OwnerReputation >= 10000 THEN 'Expert'
    ELSE 'Unknown'
  END AS ReputationLevel
FROM
  UserPostInteractions upi
  LEFT JOIN PostEditSummary pes ON upi.PostId = pes.PostId
  LEFT JOIN TopContributors tc ON upi.OwnerUserId = tc.UserId
WHERE
  upi.OwnerReputation > 100
  OR tc.ContributorRank <= 10
ORDER BY
  upi.OwnerReputation DESC,
  upi.UpVoteCountOnPost DESC,
  upi.PostCreationDate ASC;