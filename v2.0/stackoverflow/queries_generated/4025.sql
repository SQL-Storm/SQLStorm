-- {"query": "4025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1489} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserEditCounts AS (
    SELECT
      rpe.UserId,
      COUNT(DISTINCT rpe.PostId) AS NumPostsEdited,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS NumQuestionsEdited,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumAnswersEdited,
      AVG(DATEDIFF(minute, p.CreationDate, rpe.CreationDate)) AS AvgTimeToFirstEdit
    FROM RankedPostEdits AS rpe
    JOIN Posts AS p
      ON rpe.PostId = p.Id
    WHERE
      rpe.rn = 1 -- Only consider the latest edit by each user for a post
    GROUP BY
      rpe.UserId
  ),
  HighReputationUsers AS (
    SELECT
      Id
    FROM Users
    WHERE
      Reputation > 10000
  ),
  FrequentVoters AS (
    SELECT
      UserId,
      COUNT(*) AS VoteCount
    FROM Votes
    WHERE
      VoteTypeId IN (2, 3) -- UpMod, DownMod
    GROUP BY
      UserId
    HAVING
      COUNT(*) > 500
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  COALESCE(uec.NumPostsEdited, 0) AS TotalPostsEdited,
  COALESCE(uec.NumQuestionsEdited, 0) AS QuestionsEdited,
  COALESCE(uec.NumAnswersEdited, 0) AS AnswersEdited,
  COALESCE(uec.AvgTimeToFirstEdit, 0) AS AvgMinutesToFirstEdit,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = u.Id AND b.Class = 1 -- Gold badges
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.UserId = u.Id AND c.Score > 10
  ) AS HighScoringComments,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM FrequentVoters AS fv
      WHERE
        fv.UserId = u.Id
    ) THEN 'Frequent Voter'
    ELSE 'Standard Voter'
  END AS VoterStatus,
  CASE
    WHEN pht.Name IS NOT NULL THEN pht.Name
    ELSE 'No Specific Post History Type'
  END AS LastPostHistoryAction,
  CASE
    WHEN ps.Score > 0 THEN 'Positive Score'
    WHEN ps.Score < 0 THEN 'Negative Score'
    ELSE 'Zero or Null Score'
  END AS PostScoreCategory,
  LOWER(SUBSTRING(u.DisplayName FROM 1 FOR 1)) AS FirstInitial,
  CASE
    WHEN u.WebsiteUrl IS NULL THEN 'No Website'
    WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Site'
    ELSE 'Other Website'
  END AS WebsiteType,
  COALESCE(up.PostCount, 0) AS UserPostCount,
  CASE
    WHEN u.AccountId IS NULL THEN 'No Associated Account'
    WHEN EXISTS (
      SELECT
        1
      FROM HighReputationUsers AS hru
      WHERE
        hru.Id = u.Id
    ) THEN 'High Reputation'
    ELSE 'Standard Reputation'
  END AS ReputationTier
FROM Users AS u
LEFT JOIN UserEditCounts AS uec
  ON u.Id = uec.UserId
LEFT JOIN (
  SELECT
    PostId,
    MAX(CreationDate) AS LatestEditDate
  FROM PostHistory
  WHERE
    PostHistoryTypeId IN (4, 5, 6)
  GROUP BY
    PostId
) AS LatestEdits
  ON u.Id = (
    SELECT
      OwnerUserId
    FROM Posts AS p
    WHERE
      p.Id = LatestEdits.PostId
  )
LEFT JOIN PostHistoryTypes AS pht
  ON pht.Id = (
    SELECT
      PostHistoryTypeId
    FROM PostHistory AS ph
    WHERE
      ph.PostId = u.Id AND ph.CreationDate = (
        SELECT
          MAX(CreationDate)
        FROM PostHistory AS ph2
        WHERE
          ph2.PostId = u.Id
      )
  )
LEFT JOIN Posts AS ps
  ON ps.OwnerUserId = u.Id AND ps.PostTypeId = 1 -- Considering only questions for this join
LEFT JOIN (
  SELECT
    OwnerUserId,
    COUNT(*) AS PostCount
  FROM Posts
  GROUP BY
    OwnerUserId
) AS up
  ON u.Id = up.OwnerUserId
WHERE
  u.DisplayName IS NOT NULL AND u.DisplayName <> ''
  AND u.Views > 0
  AND u.Location IS NOT NULL
  AND u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 50
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  uec.NumPostsEdited,
  uec.NumQuestionsEdited,
  uec.NumAnswersEdited,
  uec.AvgTimeToFirstEdit,
  GoldBadges,
  HighScoringComments,
  VoterStatus,
  LastPostHistoryAction,
  PostScoreCategory,
  FirstInitial,
  WebsiteType,
  UserPostCount,
  ReputationTier,
  pht.Name,
  ps.Score,
  up.PostCount
HAVING
  SUM(CASE WHEN ps.PostTypeId = 1 THEN ps.AnswerCount ELSE 0 END) > 5 -- User has at least 5 answers to their questions
  OR COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId ELSE NULL END) > 0 -- User has been involved in closing posts
ORDER BY
  u.Reputation DESC,
  u.CreationDate ASC
LIMIT 100;
