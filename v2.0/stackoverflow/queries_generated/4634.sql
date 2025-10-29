-- {"query": "4634.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1426} 

WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AvgViewCount,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  CommentActivity AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      AVG(LEN(c.Text)) AS AvgCommentLength
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserContributions AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      COALESCE(upa.PostCount, 0) AS TotalPosts,
      COALESCE(ca.CommentCount, 0) AS TotalComments,
      COALESCE(upa.TotalScore, 0) AS TotalPostScore,
      COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScore,
      COALESCE(upa.AvgViewCount, 0.0) AS AveragePostViews,
      COALESCE(ca.AvgCommentLength, 0.0) AS AverageCommentLength,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, upa.LastPostDate DESC) AS ReputationRank,
      DENSE_RANK() OVER (ORDER BY u.CreationDate ASC) AS JoinOrderRank
    FROM Users AS u
      LEFT JOIN UserPostActivity AS upa
        ON u.Id = upa.OwnerUserId
      LEFT JOIN CommentActivity AS ca
        ON u.Id = ca.UserId
    WHERE
      u.DisplayName IS NOT NULL AND u.DisplayName NOT LIKE '%[^a-zA-Z0-9 ]%'
  ),
  PostAggregations AS (
    SELECT
      p.OwnerUserId,
      COUNT(CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS QuestionCount,
      COUNT(CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS AnswerCount,
      SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedPostCount,
      AVG(p.CommentCount) AS AverageCommentCountPerPost,
      MAX(p.FavoriteCount) AS MaxFavoriteCount
    FROM Posts AS p
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  )
SELECT
  uc.DisplayName,
  uc.Reputation,
  uc.CreationDate,
  uc.TotalPosts,
  uc.TotalComments,
  uc.TotalPostScore,
  uc.TotalCommentScore,
  uc.AveragePostViews,
  uc.AverageCommentLength,
  pa.QuestionCount,
  pa.AnswerCount,
  pa.ClosedPostCount,
  pa.AverageCommentCountPerPost,
  pa.MaxFavoriteCount,
  CASE
    WHEN uc.Reputation > 50000 THEN 'High'
    WHEN uc.Reputation BETWEEN 10000 AND 50000 THEN 'Medium'
    ELSE 'Low'
  END AS ReputationTier,
  CASE
    WHEN DATEDIFF(day, uc.CreationDate, GETDATE()) > 365 * 5 THEN 'Veteran'
    WHEN DATEDIFF(day, uc.CreationDate, GETDATE()) > 365 * 2 THEN 'Experienced'
    ELSE 'New'
  END AS TenureStatus,
  CASE
    WHEN uc.TotalPosts > 1000 AND uc.TotalComments > 500 THEN 'Highly Engaged'
    WHEN uc.TotalPosts > 100 AND uc.TotalComments > 50 THEN 'Moderately Engaged'
    ELSE 'Lightly Engaged'
  END AS EngagementLevel,
  pa.QuestionCount * 1.0 / NULLIF(uc.TotalPosts, 0) AS QuestionPercentage,
  CASE
    WHEN uc.TotalPostScore > 0 THEN uc.TotalPostScore / CAST(uc.TotalPosts AS REAL)
    ELSE 0.0
  END AS AvgPostScorePerUser,
  CASE
    WHEN uc.TotalCommentScore > 0 THEN uc.TotalCommentScore / CAST(uc.TotalComments AS REAL)
    ELSE 0.0
  END AS AvgCommentScorePerUser,
  uc.ReputationRank,
  uc.JoinOrderRank,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Badges AS b
      WHERE
        b.UserId = uc.UserId AND b.Name LIKE '%Gold%' AND b.Class = 1
    ) THEN 'Has Gold Badge'
    ELSE 'No Gold Badge'
  END AS GoldBadgeStatus,
  COALESCE(ua.UserDisplayName, 'Community') AS LastEditorDisplayName,
  CASE
    WHEN uc.TotalPosts = 0 AND uc.TotalComments = 0 THEN 'Inactive'
    WHEN uc.TotalPosts > 0 AND uc.TotalComments = 0 THEN 'Poster Only'
    WHEN uc.TotalPosts = 0 AND uc.TotalComments > 0 THEN 'Commenter Only'
    ELSE 'Active Contributor'
  END AS UserActivityType
FROM UserContributions AS uc
  LEFT JOIN PostAggregations AS pa
    ON uc.UserId = pa.OwnerUserId
  LEFT JOIN (
    SELECT DISTINCT
      ph.UserId,
      ph.UserDisplayName
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId = 4 OR ph.PostHistoryTypeId = 5
  ) AS ua
    ON uc.UserId = ua.UserId
WHERE
  uc.Reputation > 100 AND uc.TotalPosts > 10 AND uc.AverageCommentLength > 50
ORDER BY
  uc.Reputation DESC,
  uc.TotalPosts DESC
LIMIT 1000;
