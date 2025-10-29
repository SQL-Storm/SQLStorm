WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      pt.Name AS PostType,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus,
      COALESCE(p.AnswerCount, 0) AS AnswerCount,
      COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
      COALESCE(p.CommentCount, 0) AS CommentCount,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserQuestionSequence,
      p.Score,
      p.Tags
    FROM
      Posts p
    JOIN
      PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
      AND p.Score > 0
  ),
  AnswerDetails AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      CASE WHEN p.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END AS IsOwnerAnswer,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRankByScore
    FROM
      Posts p
    JOIN
      QuestionDetails q
      ON p.ParentId = q.QuestionId
    WHERE
      p.PostTypeId = 2
      AND p.Score >= 0
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      (
        SELECT COUNT(*) FROM Posts p_inner WHERE p_inner.OwnerUserId = u.Id
      ) AS TotalPosts,
      (
        SELECT COUNT(*) FROM Comments c_inner WHERE c_inner.UserId = u.Id
      ) AS TotalComments,
      (
        SELECT COUNT(*) FROM Votes v_inner WHERE v_inner.UserId = u.Id AND v_inner.VoteTypeId = 2
      ) AS TotalUpVotesGiven,
      (
        SELECT COUNT(*) FROM Votes v_inner WHERE v_inner.UserId = u.Id AND v_inner.VoteTypeId = 3
      ) AS TotalDownVotesGiven,
      COALESCE( (
        SELECT MAX(badge.Date) FROM Badges badge WHERE badge.UserId = u.Id AND badge.Name LIKE '%Master%'
      ), CAST('1900-01-01' AS date) ) AS LastMasterBadgeDate
    FROM
      Users u
    WHERE
      u.Reputation > 1000
  )
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  ue.DisplayName AS QuestionOwnerDisplayName,
  ue.Reputation AS QuestionOwnerReputation,
  qd.QuestionCreationDate,
  qd.PostType,
  qd.QuestionStatus,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.CommentCount,
  ad.AnswerId AS BestAnswerId,
  ad.AnswerScore AS BestAnswerScore,
  ad.AnswerCreationDate AS BestAnswerCreationDate,
  ad.AnswerRankByScore,
  ue.TotalPosts AS QuestionOwnerTotalPosts,
  ue.TotalComments AS QuestionOwnerTotalComments,
  ue.TotalUpVotesGiven AS QuestionOwnerTotalUpVotesGiven,
  ue.LastMasterBadgeDate,
  CASE
    WHEN qd.UserQuestionSequence <= 5 THEN 'Early Adopter'
    WHEN qd.UserQuestionSequence > 5 AND qd.UserQuestionSequence <= 20 THEN 'Frequent Contributor'
    ELSE 'Occasional Contributor'
  END AS UserContributionPattern
FROM
  QuestionDetails qd
LEFT JOIN
  AnswerDetails ad
  ON qd.QuestionId = ad.QuestionId AND ad.AnswerRankByScore = 1
LEFT JOIN
  UserEngagement ue
  ON qd.OwnerUserId = ue.UserId
WHERE
  ue.Reputation > 5000
  AND qd.ScoreRank BETWEEN 1 AND 1000
  AND POSITION('<sql>' IN qd.Tags) > 0
UNION
SELECT
  qd.QuestionId,
  qd.QuestionTitle,
  ue.DisplayName AS QuestionOwnerDisplayName,
  ue.Reputation AS QuestionOwnerReputation,
  qd.QuestionCreationDate,
  qd.PostType,
  qd.QuestionStatus,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.CommentCount,
  ad.AnswerId AS BestAnswerId,
  ad.AnswerScore AS BestAnswerScore,
  ad.AnswerCreationDate AS BestAnswerCreationDate,
  ad.AnswerRankByScore,
  ue.TotalPosts AS QuestionOwnerTotalPosts,
  ue.TotalComments AS QuestionOwnerTotalComments,
  ue.TotalUpVotesGiven AS QuestionOwnerTotalUpVotesGiven,
  ue.LastMasterBadgeDate,
  'Community Curated' AS UserContributionPattern
FROM
  QuestionDetails qd
JOIN
  AnswerDetails ad
  ON qd.QuestionId = ad.QuestionId AND ad.AnswerRankByScore = 1
JOIN
  UserEngagement ue
  ON ad.OwnerUserId = ue.UserId
WHERE
  ue.LastMasterBadgeDate > CAST('2023-01-01' AS date)
  AND qd.ScoreRank > 1000
  AND qd.QuestionStatus = 'Open';