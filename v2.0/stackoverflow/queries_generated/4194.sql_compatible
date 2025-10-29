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
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionsAsked,
      COUNT(DISTINCT a.Id) AS AnswersGiven,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
      AVG(p.Score) AS AvgQuestionScore,
      MAX(p.CreationDate) AS LastQuestionDate,
      MIN(u.CreationDate) AS UserFirstSeen
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts AS a
      ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId AND v.VoteTypeId = 2
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate AS PostCreationDate,
      p.OwnerUserId,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      COUNT(DISTINCT ph.Id) AS EditHistoryCount,
      MAX(ph.CreationDate) AS LastEditDate
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN Votes AS v
      ON p.Id = v.PostId
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE
      p.PostTypeId IN (1, 2)
    GROUP BY
      p.Id,
      p.Title,
      p.CreationDate,
      p.OwnerUserId
  )
SELECT
  uc.DisplayName AS UserName,
  uc.UserFirstSeen,
  uc.LastQuestionDate,
  uc.QuestionsAsked,
  uc.AnswersGiven,
  uc.UpVotesReceived,
  uc.AvgQuestionScore,
  SUM(CASE WHEN pe.PostCreationDate > uc.UserFirstSeen THEN 1 ELSE 0 END) AS QuestionsAnsweredAfterJoining,
  COUNT(DISTINCT CASE WHEN rpe.UserId IS NOT NULL THEN pe.PostId ELSE NULL END) AS PostsEditedBySelf,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = pe.PostId AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  COALESCE(pe.CommentCount, 0) AS TotalCommentsOnPosts,
  COALESCE(pe.UpVoteCount, 0) AS TotalUpvotesOnPosts,
  COALESCE(pe.DownVoteCount, 0) AS TotalDownvotesOnPosts,
  CASE
    WHEN uc.AvgQuestionScore > 100 THEN 'High Scorer'
    WHEN uc.AvgQuestionScore > 50 THEN 'Medium Scorer'
    ELSE 'Low Scorer'
  END AS ScoreCategory,
  pe.Title AS ExamplePostTitle,
  CASE
    WHEN pe.LastEditDate IS NOT NULL AND pe.PostCreationDate < pe.LastEditDate THEN
      CAST(EXTRACT(YEAR FROM pe.LastEditDate) * 10000 + EXTRACT(MONTH FROM pe.LastEditDate) * 100 + EXTRACT(DAY FROM pe.LastEditDate) AS INTEGER)
    WHEN pe.PostCreationDate IS NOT NULL THEN
      CAST(EXTRACT(YEAR FROM pe.PostCreationDate) * 10000 + EXTRACT(MONTH FROM pe.PostCreationDate) * 100 + EXTRACT(DAY FROM pe.PostCreationDate) AS INTEGER)
    ELSE 0
  END AS PostOrLastEditYearMonthDay
FROM UserContribution AS uc
LEFT JOIN PostEngagement AS pe
  ON uc.UserId = pe.OwnerUserId
LEFT JOIN RankedPostEdits AS rpe
  ON pe.PostId = rpe.PostId AND uc.UserId = rpe.UserId AND rpe.rn = 1
WHERE
  uc.QuestionsAsked > 5 OR uc.AnswersGiven > 10
GROUP BY
  uc.DisplayName,
  uc.UserFirstSeen,
  uc.LastQuestionDate,
  uc.QuestionsAsked,
  uc.AnswersGiven,
  uc.UpVotesReceived,
  uc.AvgQuestionScore,
  pe.PostCreationDate,
  pe.Title,
  pe.CommentCount,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.LastEditDate,
  pe.PostId
HAVING
  COUNT(pe.PostId) > 0
ORDER BY
  uc.UpVotesReceived DESC,
  uc.AvgQuestionScore DESC
LIMIT 100;