-- {"query": "4591.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 955}
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate,
      ROW_NUMBER() OVER (
        PARTITION BY p.ParentId
        ORDER BY p.Score DESC, p.CreationDate ASC
      ) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2
  ),
  QuestionScores AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.CreationDate AS QuestionCreationDate,
      COALESCE(p.ViewCount, 0) AS Views,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      -- extract first tag: remove leading '<' and take up to the next '>'
      SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2)) AS FirstTag
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEditCount,
      MAX(ph.CreationDate) AS LastPostHistoryDate
    FROM Users u
    LEFT JOIN PostHistory ph
      ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  ),
  TagCounts AS (
    SELECT
      t.TagName,
      t.Count AS TagUsageCount
    FROM Tags t
  )
SELECT
  qs.QuestionId,
  qs.QuestionScore,
  qs.AnswerCount,
  qs.FavoriteCount,
  qs.Views,
  qs.IsClosed,
  qs.FirstTag,
  qs.QuestionCreationDate,
  ua.DisplayName AS OwnerDisplayName,
  ua.Reputation AS OwnerReputation,
  ua.UserCreationDate AS OwnerCreationDate,
  ua.PostHistoryCount AS OwnerPostHistoryCount,
  ua.BodyEditCount AS OwnerBodyEditCount,
  ra.Score AS BestAnswerScore,
  ra.CreationDate AS BestAnswerCreationDate,
  tc.TagUsageCount,
  CASE
    WHEN qs.QuestionScore > 1000 AND qs.AnswerCount > 50 THEN 'High Engagement Question'
    WHEN qs.Views > 50000 THEN 'Popular Question'
    WHEN tc.TagUsageCount < 100 THEN 'Niche Tag Question'
    WHEN EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qs.QuestionCreationDate)) / 86400 > 365 THEN 'Old Question'
    ELSE 'Standard Question'
  END AS QuestionCategory,
  ABS(EXTRACT(EPOCH FROM (ua.LastPostHistoryDate - qs.QuestionCreationDate))) AS TimeToLastActivitySeconds,
  (qs.QuestionScore * 1.0 / NULLIF(qs.Views, 0)) * 100 AS ScorePerViewPercentage,
  ua.Reputation - qs.QuestionScore AS ReputationVsScoreDifference
FROM QuestionScores qs
LEFT JOIN UserActivity ua
  ON qs.OwnerUserId = ua.UserId
LEFT JOIN RankedAnswers ra
  ON qs.QuestionId = ra.QuestionId AND ra.AnswerRank = 1
LEFT JOIN TagCounts tc
  ON qs.FirstTag = tc.TagName
WHERE
  qs.QuestionScore >= 0
  AND qs.OwnerUserId IS NOT NULL
  AND tc.TagUsageCount IS NOT NULL
  AND ua.UserId IS NOT NULL
GROUP BY
  qs.QuestionId,
  qs.QuestionScore,
  qs.AnswerCount,
  qs.FavoriteCount,
  qs.Views,
  qs.IsClosed,
  qs.FirstTag,
  qs.QuestionCreationDate,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.PostHistoryCount,
  ua.BodyEditCount,
  ua.LastPostHistoryDate,
  ra.Score,
  ra.CreationDate,
  tc.TagUsageCount
ORDER BY qs.QuestionCreationDate DESC
LIMIT 1000;