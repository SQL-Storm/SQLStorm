-- {"query": "4340.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 950} 

WITH
  QuestionEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.Comment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId = 5 -- Edit Body
  ),
  TopQuestionEditors AS (
    SELECT
      UserId,
      COUNT(DISTINCT PostId) AS NumQuestionsEdited
    FROM
      QuestionEdits
    WHERE
      rn = 1
    GROUP BY
      UserId
    HAVING
      COUNT(DISTINCT PostId) > 5
  ),
  PostScores AS (
    SELECT
      p.Id AS PostId,
      p.Score,
      SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
      p.CreationDate,
      p.OwnerUserId,
      pt.Name AS PostTypeName
    FROM
      Posts AS p
    JOIN
      PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.Score > 0
    GROUP BY
      p.Id,
      p.Score,
      p.CreationDate,
      p.OwnerUserId,
      pt.Name
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ps.PostId) AS TotalPostsScored,
      SUM(ps.Score) AS TotalScoreFromPosts,
      MAX(ps.CreationDate) AS LastPostScoreDate
    FROM
      Users AS u
    JOIN
      PostScores AS ps
      ON u.Id = ps.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
    HAVING
      COUNT(DISTINCT ps.PostId) > 10
  )
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.TotalPostsScored,
  ua.TotalScoreFromPosts,
  ua.LastPostScoreDate,
  COALESCE(tqe.NumQuestionsEdited, 0) AS NumberOfQuestionsHeavilyEdited,
  CASE
    WHEN ua.TotalScoreFromPosts > 1000 THEN 'High Performer'
    WHEN ua.TotalScoreFromPosts > 500 THEN 'Medium Performer'
    ELSE 'Emerging'
  END AS PerformanceTier,
  CAST(ua.TotalScoreFromPosts AS DECIMAL(18, 2)) / ua.TotalPostsScored AS AverageScorePerPost,
  LENGTH(ua.DisplayName) AS DisplayNameLength,
  CASE
    WHEN ua.LastPostScoreDate < DATE('now', '-1 year') THEN 'Inactive'
    ELSE 'Active'
  END AS ActivityStatus
FROM
  UserActivity AS ua
LEFT JOIN
  TopQuestionEditors AS tqe
  ON ua.UserId = tqe.UserId
WHERE
  ua.Reputation > 100
  AND ua.UserCreationDate < DATE('now', '-6 months')
UNION ALL
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  0 AS TotalPostsScored,
  0 AS TotalScoreFromPosts,
  NULL AS LastPostScoreDate,
  0 AS NumberOfQuestionsHeavilyEdited,
  'New User' AS PerformanceTier,
  0.00 AS AverageScorePerPost,
  LENGTH(u.DisplayName) AS DisplayNameLength,
  'New' AS ActivityStatus
FROM
  Users AS u
WHERE
  u.Reputation <= 100
  AND u.CreationDate >= DATE('now', '-6 months')
ORDER BY
  Reputation DESC,
  TotalScoreFromPosts DESC;
