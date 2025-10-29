-- {"query": "4408.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1542} 

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
      Posts AS p
      LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.OwnerUserId IS NOT NULL
      AND p.Score > 0
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
      AVG(rp_ans.Score) OVER (PARTITION BY rp.PostId) AS AvgAnswerScore,
      COUNT(rp_ans.Id) OVER (PARTITION BY rp.PostId) AS AnswerCountForQuestion,
      rp.RowNum
    FROM
      RankedPosts AS rp
      LEFT JOIN Posts AS rp_ans
        ON rp.PostId = rp_ans.ParentId AND rp_ans.PostTypeId = 2 -- Only consider answers
    WHERE
      rp.PostTypeId = 1 -- Filter for questions
    GROUP BY
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
      rp.RowNum
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserDisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
      SUM(p.Score) AS TotalScore,
      MAX(p.LastActivityDate) AS LastUserActivityDate,
      CASE
        WHEN SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) > SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) THEN 'Answerer'
        WHEN SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) > SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) THEN 'Questioner'
        ELSE 'Balanced'
      END AS PrimaryRole
    FROM
      Users AS u
      LEFT JOIN Posts AS p
        ON u.Id = p.OwnerUserId
    WHERE
      u.Id IN (SELECT OwnerUserId FROM RankedPosts WHERE RowNum <= 1000) -- Limit to top 1000 users based on post recency
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
  DATE_PART('day', qm.LastActivityDate - qm.CreationDate) AS PostAgeDays,
  CASE
    WHEN qm.OwnerReputation > 100000 THEN 'HighRep'
    WHEN qm.OwnerReputation BETWEEN 50000 AND 100000 THEN 'MidRep'
    ELSE 'LowRep'
  END AS ReputationBucket,
  COALESCE(ua.UserDisplayName, 'Unknown User') AS FinalUserDisplayName,
  CASE
    WHEN qm.PostScore IS NULL THEN 'NoScore'
    WHEN qm.PostScore > 100 THEN 'HighScore'
    WHEN qm.PostScore > 10 THEN 'MidScore'
    ELSE 'LowScore'
  END AS ScoreCategory,
  CASE
    WHEN qm.AvgAnswerScore IS NULL THEN 0
    ELSE ROUND(qm.AvgAnswerScore, 2)
  END AS RoundedAvgAnswerScore,
  -- Example of a complicated string expression and NULL logic
  CASE
    WHEN qm.OwnerDisplayName LIKE '% %' THEN UPPER(SUBSTRING(qm.OwnerDisplayName FROM 1 FOR POSITION(' ' IN qm.OwnerDisplayName) - 1)) || '-' || LOWER(SUBSTRING(qm.OwnerDisplayName FROM POSITION(' ' IN qm.OwnerDisplayName) + 1))
    ELSE UPPER(qm.OwnerDisplayName)
  END AS FormattedOwnerName,
  CASE
    WHEN qm.PostFavoriteCount IS NULL AND qm.PostCommentCount IS NULL THEN 'NoEngagement'
    WHEN qm.PostFavoriteCount > 0 OR qm.PostCommentCount > 0 THEN 'Engaged'
    ELSE 'Passive'
  END AS EngagementLevel
FROM
  QuestionMetrics AS qm
  JOIN UserActivity AS ua
    ON qm.OwnerUserId = ua.UserId
WHERE
  qm.RowNum <= 500 -- Further limit to top 500 questions by recency for the final result
  AND qm.AnswerCountForQuestion > 0 -- Only consider questions that have at least one answer
  AND ua.Reputation > 100 -- Filter out users with very low reputation
ORDER BY
  qm.RankWithinType,
  qm.PostCreationDate DESC
LIMIT 100; -- Final limit for the benchmark output
