-- {"query": "4504.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1425} 

WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      pt.Name AS PostType,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS QuestionStatus,
      COALESCE(p.AnswerCount, 0) AS AnswerCount,
      COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
      COALESCE(p.CommentCount, 0) AS CommentCount,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserQuestionSequence
    FROM
      Posts AS p
    JOIN
      PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= DATEADD(year, -5, GETDATE())
      AND p.Score > 0
  ),
  AnswerDetails AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      CASE
        WHEN p.OwnerUserId = q.OwnerUserId THEN 1
        ELSE 0
      END AS IsOwnerAnswer,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRankByScore
    FROM
      Posts AS p
    JOIN
      QuestionDetails AS q
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
        SELECT
          COUNT(*)
        FROM
          Posts AS p_inner
        WHERE
          p_inner.OwnerUserId = u.Id
      ) AS TotalPosts,
      (
        SELECT
          COUNT(*)
        FROM
          Comments AS c_inner
        WHERE
          c_inner.UserId = u.Id
      ) AS TotalComments,
      (
        SELECT
          COUNT(*)
        FROM
          Votes AS v_inner
        WHERE
          v_inner.UserId = u.Id
          AND v_inner.VoteTypeId = 2 /* UpVote */
      ) AS TotalUpVotesGiven,
      (
        SELECT
          COUNT(*)
        FROM
          Votes AS v_inner
        WHERE
          v_inner.UserId = u.Id
          AND v_inner.VoteTypeId = 3 /* DownVote */
      ) AS TotalDownVotesGiven,
      ISNULL( (
        SELECT
          MAX(Badge.Date)
        FROM
          Badges AS Badge
        WHERE
          Badge.UserId = u.Id
          AND Badge.Name LIKE '%Master%'
      ), '1900-01-01'
      ) AS LastMasterBadgeDate
    FROM
      Users AS u
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
  ud.TotalPosts AS QuestionOwnerTotalPosts,
  ud.TotalComments AS QuestionOwnerTotalComments,
  ud.TotalUpVotesGiven AS QuestionOwnerTotalUpVotesGiven,
  ud.LastMasterBadgeDate,
  CASE
    WHEN qd.UserQuestionSequence <= 5 THEN 'Early Adopter'
    WHEN qd.UserQuestionSequence > 5 AND qd.UserQuestionSequence <= 20 THEN 'Frequent Contributor'
    ELSE 'Occasional Contributor'
  END AS UserContributionPattern
FROM
  QuestionDetails AS qd
LEFT OUTER JOIN
  AnswerDetails AS ad
  ON qd.QuestionId = ad.QuestionId AND ad.AnswerRankByScore = 1
LEFT OUTER JOIN
  UserEngagement AS ue
  ON qd.OwnerUserId = ue.UserId
WHERE
  ue.Reputation > 5000
  AND qd.ScoreRank BETWEEN 1 AND 1000
  AND CHARINDEX('<' + 'sql' + '>', qd.Tags) > 0
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
  ud.TotalPosts AS QuestionOwnerTotalPosts,
  ud.TotalComments AS QuestionOwnerTotalComments,
  ud.TotalUpVotesGiven AS QuestionOwnerTotalUpVotesGiven,
  ud.LastMasterBadgeDate,
  'Community Curated' AS UserContributionPattern
FROM
  QuestionDetails AS qd
JOIN
  AnswerDetails AS ad
  ON qd.QuestionId = ad.QuestionId AND ad.AnswerRankByScore = 1
JOIN
  UserEngagement AS ue
  ON ad.OwnerUserId = ue.UserId
WHERE
  ue.LastMasterBadgeDate > '2023-01-01'
  AND qd.ScoreRank > 1000
  AND qd.QuestionStatus = 'Open';
