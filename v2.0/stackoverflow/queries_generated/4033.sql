-- {"query": "4033.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1128} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
  ),
  UserPostInteractions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      (
        SELECT
          COUNT(c.Id)
        FROM
          Comments AS c
        WHERE
          c.PostId = p.Id AND c.UserId IS NOT NULL
      ) AS CommentCountOnPost,
      (
        SELECT
          COUNT(v.Id)
        FROM
          Votes AS v
        WHERE
          v.PostId = p.Id AND v.VoteTypeId = 2 /* UpMod */
      ) AS UpVoteCountOnPost,
      p.AnswerCount,
      p.FavoriteCount,
      COALESCE(u.Reputation, 0) AS OwnerReputation,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      u.DisplayName AS OwnerDisplayName
    FROM
      Posts AS p
      LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 /* Questions */
  ),
  PostEditSummary AS (
    SELECT
      rpe.PostId,
      COUNT(rpe.UserId) AS NumberOfUniqueEditors,
      MAX(rpe.CreationDate) AS LastEditDate,
      DATEDIFF(
        minute,
        MIN(rpe.CreationDate),
        MAX(rpe.CreationDate)
      ) AS TimeBetweenFirstAndLastEditMinutes
    FROM
      RankedPostEdits AS rpe
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
      Users AS u
      JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    WHERE
      p.PostTypeId = 2 /* Answers */
      AND p.CreationDate >= DATEADD(month, -12, GETDATE())
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
    WHEN DATEDIFF(hour, upi.PostCreationDate, pes.LastEditDate) < 24 THEN 'Within 24 Hours'
    WHEN DATEDIFF(day, upi.PostCreationDate, pes.LastEditDate) < 7 THEN 'Within 7 Days'
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
  UserPostInteractions AS upi
  LEFT JOIN PostEditSummary AS pes
  ON upi.PostId = pes.PostId
  LEFT JOIN TopContributors AS tc
  ON upi.OwnerUserId = tc.UserId
WHERE
  upi.OwnerReputation > 100
  OR tc.ContributorRank <= 10
ORDER BY
  upi.OwnerReputation DESC,
  upi.UpVoteCountOnPost DESC,
  upi.PostCreationDate ASC;
