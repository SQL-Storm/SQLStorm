WITH
  AnswerQuality AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn_score,
      AVG(c.Score) OVER (PARTITION BY p.ParentId) AS AvgCommentScoreForQuestion,
      COUNT(c.Id) OVER (PARTITION BY p.ParentId) AS TotalCommentsForQuestion,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS NextAnswerScore
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      pt.Name = 'Answer' AND p.ParentId IS NOT NULL
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.Tags,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionCreationDate,
      q.AnswerCount,
      q.FavoriteCount,
      q.Score AS QuestionScore,
      CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (19, 20)
      ) AS ProtectionCount,
      RANK() OVER (ORDER BY q.FavoriteCount DESC) AS QuestionRankByFavorites
    FROM Posts q
    WHERE q.PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      MAX(p.LastActivityDate) AS LastPostActivityDate,
      SUM(CASE WHEN p.Score > 100 THEN 1 ELSE 0 END) AS HighScorePostCount
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  )
SELECT
  qd.Title AS QuestionTitle,
  ua.DisplayName AS QuestionOwnerDisplayName,
  qd.QuestionCreationDate,
  qd.QuestionScore,
  qd.IsClosed,
  qd.ProtectionCount,
  aq.Score AS BestAnswerScore,
  aq.AvgCommentScoreForQuestion,
  ua.Reputation AS QuestionOwnerReputation,
  CASE
    WHEN aq.rn_score = 1 THEN 'Best Answer'
    WHEN aq.rn_score BETWEEN 2 AND 5 THEN 'Good Answer'
    ELSE 'Other Answer'
  END AS AnswerCategory,
  CASE
    WHEN qd.QuestionRankByFavorites < 1000 THEN 'Top 1000 Favorite Question'
    ELSE 'Regular Favorite Question'
  END AS FavoriteQuestionStatus,
  (
    ua.HighScorePostCount * 1.0 / NULLIF(ua.TotalPostsOwned, 0)
  ) AS HighScorePostRatio,
  COALESCE(aq.TotalCommentsForQuestion, 0) AS ActualTotalComments,
  CAST((CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate) AS interval) AS QuestionAgeInterval,
  EXTRACT(DAY FROM CAST((CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate) AS interval)) 
    + EXTRACT(EPOCH FROM CAST((CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate) AS interval)) / 86400 - FLOOR(EXTRACT(EPOCH FROM CAST((CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate) AS interval)) / 86400) AS QuestionAgeInDays_Fraction,
  CASE
    WHEN aq.Score > aq.NextAnswerScore * 1.2 THEN 'Significantly Better Than Next'
    ELSE 'Similar to Next'
  END AS AnswerPerformanceDelta,
  UPPER(SUBSTRING(qd.Tags FROM 2 FOR (POSITION('><' IN qd.Tags) - 2))) AS PrimaryTag,
  CASE
    WHEN qd.FavoriteCount > 50 AND qd.ProtectionCount > 0 THEN 'Highly Frequented & Protected'
    WHEN qd.IsClosed = 1 THEN 'Closed Question'
    WHEN ua.Reputation > 100000 THEN 'High Reputation Owner'
    ELSE 'Standard Question'
  END AS QuestionStatusCategory
FROM QuestionDetails qd
LEFT JOIN AnswerQuality aq
  ON qd.QuestionId = aq.QuestionId AND aq.rn_score = 1
LEFT JOIN UserActivity ua
  ON qd.QuestionOwnerUserId = ua.UserId
WHERE
  qd.QuestionScore > 0 AND qd.AnswerCount > 0 AND
  (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate)) / 86400) > 7
  AND ua.Reputation > 500

UNION

SELECT
  qd.Title AS QuestionTitle,
  ua.DisplayName AS QuestionOwnerDisplayName,
  qd.QuestionCreationDate,
  qd.QuestionScore,
  qd.IsClosed,
  qd.ProtectionCount,
  aq.Score AS BestAnswerScore,
  aq.AvgCommentScoreForQuestion,
  ua.Reputation AS QuestionOwnerReputation,
  CASE
    WHEN aq.rn_score = 1 THEN 'Best Answer'
    WHEN aq.rn_score BETWEEN 2 AND 5 THEN 'Good Answer'
    ELSE 'Other Answer'
  END AS AnswerCategory,
  CASE
    WHEN qd.QuestionRankByFavorites < 1000 THEN 'Top 1000 Favorite Question'
    ELSE 'Regular Favorite Question'
  END AS FavoriteQuestionStatus,
  (
    ua.HighScorePostCount * 1.0 / NULLIF(ua.TotalPostsOwned, 0)
  ) AS HighScorePostRatio,
  COALESCE(aq.TotalCommentsForQuestion, 0) AS ActualTotalComments,
  CAST((CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate) AS interval) AS QuestionAgeInterval,
  EXTRACT(DAY FROM CAST((CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate) AS interval)) 
    + EXTRACT(EPOCH FROM CAST((CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate) AS interval)) / 86400 - FLOOR(EXTRACT(EPOCH FROM CAST((CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate) AS interval)) / 86400) AS QuestionAgeInDays_Fraction,
  CASE
    WHEN aq.Score > aq.NextAnswerScore * 1.2 THEN 'Significantly Better Than Next'
    ELSE 'Similar to Next'
  END AS AnswerPerformanceDelta,
  UPPER(SUBSTRING(qd.Tags FROM 2 FOR (POSITION('><' IN qd.Tags) - 2))) AS PrimaryTag,
  CASE
    WHEN qd.FavoriteCount > 50 AND qd.ProtectionCount > 0 THEN 'Highly Frequented & Protected'
    WHEN qd.IsClosed = 1 THEN 'Closed Question'
    WHEN ua.Reputation > 100000 THEN 'High Reputation Owner'
    ELSE 'Standard Question'
  END AS QuestionStatusCategory
FROM QuestionDetails qd
JOIN AnswerQuality aq
  ON qd.QuestionId = aq.QuestionId AND aq.rn_score > 1 AND aq.rn_score <= 5
JOIN UserActivity ua
  ON qd.QuestionOwnerUserId = ua.UserId
WHERE
  qd.QuestionScore > 0 AND qd.AnswerCount > 0 AND
  (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qd.QuestionCreationDate)) / 86400) > 7
  AND ua.Reputation > 500;