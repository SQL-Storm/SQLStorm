-- {"query": "4931.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1203} 

WITH
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByReputation,
      AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      pt.Name AS PostType,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostSequence
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.CreationDate >= DATE('now', '-1 year')
  ),
  HighValueUsers AS (
    SELECT
      UserId,
      DisplayName
    FROM UserActivity
    WHERE
      RankByReputation <= 100
      AND AvgPostScore > 5
  )
SELECT
  ua.DisplayName,
  ua.TotalPosts,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount,
  ua.BadgeCount,
  ua.RankByReputation,
  ua.AvgPostScore,
  COUNT(DISTINCT pe.PostId) AS PostsInLastYear,
  SUM(pe.Score) AS TotalScoreInLastYear,
  MAX(pe.ViewCount) AS MaxViewCountInLastYear,
  CASE
    WHEN ua.DisplayName LIKE '% %' THEN UPPER(SUBSTR(ua.DisplayName, 1, INSTR(ua.DisplayName, ' ') - 1))
    ELSE UPPER(ua.DisplayName)
  END AS FirstName,
  COALESCE(hvu.UserId, -1) AS IsHighValueUserIndicator
FROM UserActivity AS ua
LEFT JOIN PostEngagement AS pe
  ON ua.UserId = pe.OwnerUserId
LEFT JOIN HighValueUsers AS hvu
  ON ua.UserId = hvu.UserId
WHERE
  ua.TotalPosts > 10
GROUP BY
  ua.DisplayName,
  ua.TotalPosts,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount,
  ua.BadgeCount,
  ua.RankByReputation,
  ua.AvgPostScore,
  FirstName,
  IsHighValueUserIndicator
HAVING
  COUNT(DISTINCT pe.PostId) > 5
UNION ALL
SELECT
  'Summary Statistics' AS DisplayName,
  COUNT(DISTINCT p.OwnerUserId) AS TotalPosts,
  COUNT(DISTINCT CASE WHEN pt.Name = 'Question' THEN p.OwnerUserId ELSE NULL END) AS QuestionCount,
  COUNT(DISTINCT CASE WHEN pt.Name = 'Answer' THEN p.OwnerUserId ELSE NULL END) AS AnswerCount,
  COUNT(DISTINCT c.UserId) AS CommentCount,
  COUNT(DISTINCT b.UserId) AS BadgeCount,
  AVG(ua.RankByReputation) AS RankByReputation,
  AVG(ua.AvgPostScore) AS AvgPostScore,
  COUNT(DISTINCT pe.PostId) AS PostsInLastYear,
  SUM(pe.Score) AS TotalScoreInLastYear,
  MAX(pe.ViewCount) AS MaxViewCountInLastYear,
  'N/A' AS FirstName,
  -1 AS IsHighValueUserIndicator
FROM UserActivity AS ua
LEFT JOIN Posts AS p
  ON ua.UserId = p.OwnerUserId
LEFT JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Comments AS c
  ON ua.UserId = c.UserId
LEFT JOIN Badges AS b
  ON ua.UserId = b.UserId
LEFT JOIN PostEngagement AS pe
  ON ua.UserId = pe.OwnerUserId
WHERE
  ua.TotalPosts > 10;
