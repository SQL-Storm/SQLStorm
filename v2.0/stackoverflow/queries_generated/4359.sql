-- {"query": "4359.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1459} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      pht.Name AS HistoryType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS TotalPosts,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      Id
    FROM Users
    WHERE
      Reputation > 10000
  ),
  PostsWithTagInfo AS (
    SELECT
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.AnswerCount,
      p.CommentCount,
      p.Score,
      p.ViewCount,
      CASE
        WHEN p.Tags IS NULL THEN 'NO_TAGS'
        ELSE REPLACE(REPLACE(p.Tags, '<', ''), '>', '')
      END AS FormattedTags,
      u.DisplayName AS OwnerDisplayName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
  )
SELECT
  p.Id AS PostId,
  p.Title,
  p.FormattedTags,
  p.OwnerDisplayName,
  p.TotalPosts,
  p.QuestionCount,
  p.AnswerCount,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  CASE WHEN p.IsClosed = 1 THEN 'Yes' ELSE 'No' END AS ClosedStatus,
  rpe.CreationDate AS LatestEditDate,
  rpe.HistoryType AS LatestEditType,
  u.Reputation AS OwnerReputation,
  COALESCE(p.PreviousPostScore, 0) AS PreviousPostScore,
  COALESCE(p.NextPostScore, 0) AS NextPostScore,
  CASE
    WHEN p.Score > 0 AND p.AnswerCount > 0 THEN CAST(p.Score AS REAL) / p.AnswerCount
    WHEN p.Score > 0 THEN CAST(p.Score AS REAL)
    ELSE 0.0
  END AS ScoreToAnswerRatio,
  CASE
    WHEN p.OwnerReputation > 5000 AND p.Score > 10 THEN 'High Reputation & High Score'
    WHEN p.OwnerReputation < 1000 AND p.AnswerCount > 5 THEN 'Low Reputation & Many Answers'
    ELSE 'Standard'
  END AS UserPostCategory,
  CASE
    WHEN p.FormattedTags LIKE '%sql%' THEN 'ContainsSQL'
    WHEN p.FormattedTags LIKE '%performance%' THEN 'ContainsPerformance'
    ELSE 'OtherTags'
  END AS TagCategory
FROM PostsWithTagInfo AS p
JOIN UserPostCounts AS upc
  ON p.OwnerUserId = upc.OwnerUserId
LEFT JOIN RankedPostEdits AS rpe
  ON p.Id = rpe.PostId AND rpe.rn = 1
JOIN Users AS u
  ON p.OwnerUserId = u.Id
WHERE
  p.OwnerUserId IN (SELECT Id FROM HighReputationUsers)
  AND p.Score > 50
UNION ALL
SELECT
  p.Id AS PostId,
  p.Title,
  p.FormattedTags,
  p.OwnerDisplayName,
  p.TotalPosts,
  p.QuestionCount,
  p.AnswerCount,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  CASE WHEN p.IsClosed = 1 THEN 'Yes' ELSE 'No' END AS ClosedStatus,
  rpe.CreationDate AS LatestEditDate,
  rpe.HistoryType AS LatestEditType,
  u.Reputation AS OwnerReputation,
  COALESCE(p.PreviousPostScore, 0) AS PreviousPostScore,
  COALESCE(p.NextPostScore, 0) AS NextPostScore,
  CASE
    WHEN p.Score > 0 AND p.AnswerCount > 0 THEN CAST(p.Score AS REAL) / p.AnswerCount
    WHEN p.Score > 0 THEN CAST(p.Score AS REAL)
    ELSE 0.0
  END AS ScoreToAnswerRatio,
  CASE
    WHEN p.OwnerReputation > 5000 AND p.Score > 10 THEN 'High Reputation & High Score'
    WHEN p.OwnerReputation < 1000 AND p.AnswerCount > 5 THEN 'Low Reputation & Many Answers'
    ELSE 'Standard'
  END AS UserPostCategory,
  CASE
    WHEN p.FormattedTags LIKE '%sql%' THEN 'ContainsSQL'
    WHEN p.FormattedTags LIKE '%performance%' THEN 'ContainsPerformance'
    ELSE 'OtherTags'
  END AS TagCategory
FROM PostsWithTagInfo AS p
JOIN UserPostCounts AS upc
  ON p.OwnerUserId = upc.OwnerUserId
LEFT JOIN RankedPostEdits AS rpe
  ON p.Id = rpe.PostId AND rpe.rn = 1
JOIN Users AS u
  ON p.OwnerUserId = u.Id
WHERE
  p.OwnerUserId NOT IN (SELECT Id FROM HighReputationUsers)
  AND p.AnswerCount > 10
  AND p.ViewCount > 1000;
