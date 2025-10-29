WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.LastActivityDate,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.FavoriteCount DESC) AS RankWithinType,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM
      Posts p
      LEFT JOIN Users u
        ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2)
      AND p.OwnerUserId IS NOT NULL
      AND p.Score > 0
  ),
  AnswerAgg AS (
    SELECT
      ParentId AS QuestionId,
      COUNT(Id) AS AnswerCountForQuestion,
      AVG(Score) AS AvgAnswerScore
    FROM
      Posts
    WHERE
      PostTypeId = 2
    GROUP BY
      ParentId
  ),
  QuestionMetrics AS (
    SELECT
      rp.PostId,
      rp.OwnerUserId,
      rp.OwnerDisplayName,
      rp.OwnerReputation,
      rp.Score,
      rp.CommentCount,
      rp.FavoriteCount,
      rp.CreationDate,
      rp.LastActivityDate,
      rp.RankWithinType,
      COALESCE(aa.AvgAnswerScore, NULL) AS AvgAnswerScore,
      COALESCE(aa.AnswerCountForQuestion, 0) AS AnswerCountForQuestion,
      rp.RowNum,
      rp.PostTypeId
    FROM
      RankedPosts rp
      LEFT JOIN AnswerAgg aa
        ON rp.PostId = aa.QuestionId
    WHERE
      rp.PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserDisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
      COALESCE(SUM(p.Score),0) AS TotalScore,
      MAX(p.LastActivityDate) AS LastUserActivityDate,
      CASE
        WHEN SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) > SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) THEN 'Answerer'
        WHEN SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) > SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) THEN 'Questioner'
        ELSE 'Balanced'
      END AS PrimaryRole
    FROM
      Users u
      LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
    WHERE
      u.Id IN (SELECT OwnerUserId FROM RankedPosts WHERE RowNum <= 1000)
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  )
SELECT
  qm.PostId,
  qm.OwnerDisplayName,
  qm.OwnerReputation,
  qm.Score AS PostScore,
  qm.CommentCount AS PostCommentCount,
  qm.FavoriteCount AS PostFavoriteCount,
  qm.CreationDate AS PostCreationDate,
  qm.LastActivityDate AS PostLastActivityDate,
  qm.RankWithinType,
  qm.AvgAnswerScore,
  qm.AnswerCountForQuestion,
  ua.QuestionCount AS UserTotalQuestions,
  ua.AnswerCount AS UserTotalAnswers,
  ua.TotalScore AS UserTotalScore,
  ua.LastUserActivityDate AS UserLastActivityDate,
  ua.PrimaryRole,
  (qm.Score * 1.0 / NULLIF(qm.AnswerCountForQuestion, 0)) AS ScorePerAnswer,
  EXTRACT(day FROM (qm.LastActivityDate - qm.CreationDate)) AS PostAgeDays,
  CASE
    WHEN qm.OwnerReputation > 100000 THEN 'HighRep'
    WHEN qm.OwnerReputation BETWEEN 50000 AND 100000 THEN 'MidRep'
    ELSE 'LowRep'
  END AS ReputationBucket,
  COALESCE(ua.UserDisplayName, 'Unknown User') AS FinalUserDisplayName,
  CASE
    WHEN qm.Score IS NULL THEN 'NoScore'
    WHEN qm.Score > 100 THEN 'HighScore'
    WHEN qm.Score > 10 THEN 'MidScore'
    ELSE 'LowScore'
  END AS ScoreCategory,
  CASE
    WHEN qm.AvgAnswerScore IS NULL THEN 0
    ELSE ROUND(CAST(qm.AvgAnswerScore AS NUMERIC), 2)
  END AS RoundedAvgAnswerScore,
  CASE
    WHEN qm.OwnerDisplayName LIKE '% %' THEN UPPER(SUBSTRING(qm.OwnerDisplayName FROM 1 FOR POSITION(' ' IN qm.OwnerDisplayName) - 1)) || '-' || LOWER(SUBSTRING(qm.OwnerDisplayName FROM POSITION(' ' IN qm.OwnerDisplayName) + 1))
    ELSE UPPER(qm.OwnerDisplayName)
  END AS FormattedOwnerName,
  CASE
    WHEN qm.FavoriteCount IS NULL AND qm.CommentCount IS NULL THEN 'NoEngagement'
    WHEN qm.FavoriteCount > 0 OR qm.CommentCount > 0 THEN 'Engaged'
    ELSE 'Passive'
  END AS EngagementLevel
FROM
  QuestionMetrics qm
  JOIN UserActivity ua
    ON qm.OwnerUserId = ua.UserId
WHERE
  qm.RowNum <= 500
  AND qm.AnswerCountForQuestion > 0
  AND ua.Reputation > 100
ORDER BY
  qm.RankWithinType,
  qm.CreationDate DESC
LIMIT 100;