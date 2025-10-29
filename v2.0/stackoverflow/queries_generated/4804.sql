-- {"query": "4804.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1211} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
  ),
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS AnswerCount,
      SUM(CASE WHEN pt.Name = 'Question' THEN p.Score ELSE 0 END) AS TotalQuestionScore,
      SUM(CASE WHEN pt.Name = 'Answer' THEN p.Score ELSE 0 END) AS TotalAnswerScore,
      AVG(CASE WHEN pt.Name = 'Question' THEN p.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
      MAX(CASE WHEN pt.Name = 'Question' THEN p.ViewCount ELSE NULL END) AS MaxQuestionViewCount
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  LatestUserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      MAX(p.LastActivityDate) AS LastPostActivityDate,
      COUNT(DISTINCT p.Id) AS TotalPosts
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  UserEngagement AS (
    SELECT
      ups.OwnerUserId,
      COALESCE(l.TotalPosts, 0) AS TotalPosts,
      COALESCE(ups.QuestionCount, 0) AS QuestionCount,
      COALESCE(ups.AnswerCount, 0) AS AnswerCount,
      COALESCE(ups.TotalQuestionScore, 0) AS TotalQuestionScore,
      COALESCE(ups.TotalAnswerScore, 0) AS TotalAnswerScore,
      COALESCE(ups.AvgQuestionViewCount, 0) AS AvgQuestionViewCount,
      COALESCE(ups.MaxQuestionViewCount, 0) AS MaxQuestionViewCount,
      COALESCE(l.UserCreationDate, '1900-01-01') AS UserCreationDate,
      COALESCE(l.LastPostActivityDate, '1900-01-01') AS LastPostActivityDate
    FROM UserPostStats AS ups
    FULL OUTER JOIN LatestUserActivity AS l
      ON ups.OwnerUserId = l.UserId
  )
SELECT
  rp.PostId,
  rp.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  pt.Name AS PostType,
  rp.CreationDate AS PostCreationDate,
  rp.Score AS PostScore,
  rp.ViewCount AS PostViewCount,
  rp.AnswerCount AS PostAnswerCount,
  rp.FavoriteCount AS PostFavoriteCount,
  ue.QuestionCount,
  ue.AnswerCount AS UserAnswerCount,
  ue.TotalQuestionScore,
  ue.TotalAnswerScore,
  ue.AvgQuestionViewCount,
  ue.MaxQuestionViewCount,
  ue.UserCreationDate,
  ue.LastPostActivityDate,
  CASE
    WHEN rp.Score > 1000 THEN 'High Score'
    WHEN rp.ViewCount > 100000 THEN 'High View Count'
    WHEN rp.AnswerCount > 50 THEN 'High Answer Count'
    WHEN DATEDIFF(day, rp.CreationDate, GETDATE()) > 365 * 5 THEN 'Old Post'
    WHEN DATEDIFF(day, ue.LastPostActivityDate, GETDATE()) < 7 THEN 'Recently Active User'
    ELSE 'Standard'
  END AS PostCategory,
  CASE
    WHEN rp.PostTypeId = 1 AND rp.Score > 0 THEN CONCAT(rp.OwnerUserId, '_', rp.Score)
    WHEN rp.PostTypeId = 2 AND rp.Score > 0 THEN CONCAT(rp.OwnerUserId, '_', rp.Score * -1)
    ELSE CONCAT(rp.OwnerUserId, '_0')
  END AS UserScoreIdentifier
FROM RankedPosts AS rp
JOIN Users AS u
  ON rp.OwnerUserId = u.Id
LEFT JOIN PostTypes AS pt
  ON rp.PostTypeId = pt.Id
LEFT JOIN UserEngagement AS ue
  ON rp.OwnerUserId = ue.OwnerUserId
WHERE
  rp.rn <= 100 -- Limit to top 100 recent posts per type for demonstration
ORDER BY
  rp.PostTypeId,
  rp.CreationDate DESC;
