-- {"query": "4497.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1212} 

WITH
  RankedUserPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
  ),
  UserContributions AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      (
        SELECT
          COUNT(*)
        FROM Posts AS p_inner
        WHERE
          p_inner.OwnerUserId = u.Id
      ) AS TotalPosts,
      (
        SELECT
          COUNT(DISTINCT b.Id)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadges,
      (
        SELECT
          SUM(p_comments.Score)
        FROM Posts AS p_outer
        JOIN Comments AS p_comments
          ON p_outer.Id = p_comments.PostId
        WHERE
          p_outer.OwnerUserId = u.Id
      ) AS TotalCommentScore
    FROM Users AS u
    WHERE
      u.Id IN (SELECT DISTINCT
          OwnerUserId
        FROM Posts
        WHERE
          OwnerUserId IS NOT NULL)
  ),
  PostWithDetails AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.Title,
      p.Tags,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate,
      p.ClosedDate,
      DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS PostActivityDurationDays,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.FavoriteCount > 100 THEN 'Popular'
        WHEN p.Score > 10 THEN 'Highly Rated'
        ELSE 'Regular'
      END AS PostStatusCategory
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId IN (1, 2) -- Questions and Answers
  )
SELECT
  uc.UserId,
  uc.DisplayName,
  uc.Reputation,
  uc.UserCreationDate,
  uc.TotalPosts,
  uc.GoldBadges,
  uc.TotalCommentScore,
  COUNT(CASE WHEN pwd.PostTypeId = 1 THEN pwd.PostId END) AS NumberOfQuestions,
  COUNT(CASE WHEN pwd.PostTypeId = 2 THEN pwd.PostId END) AS NumberOfAnswers,
  AVG(pwd.Score) AS AveragePostScore,
  SUM(pwd.ViewCount) AS TotalViewCount,
  SUM(pwd.FavoriteCount) AS TotalFavoriteCount,
  MAX(pwd.LastActivityDate) AS LastActivityOnSite,
  CASE
    WHEN uc.Reputation > 50000 THEN 'Expert'
    WHEN uc.Reputation > 10000 THEN 'Experienced'
    WHEN uc.Reputation > 1000 THEN 'Intermediate'
    ELSE 'Beginner'
  END AS ReputationLevel,
  CASE
    WHEN uc.TotalPosts > 1000 AND uc.GoldBadges >= 5 THEN 'Highly Engaged'
    ELSE 'Standard Engagement'
  END AS EngagementLevel,
  COALESCE(
    (
      SELECT
        TOP 1
        ph.Comment
      FROM PostHistory AS ph
      WHERE
        ph.PostId = pwd.PostId
        AND ph.PostHistoryTypeId = 10 -- Post Closed
      ORDER BY
        ph.CreationDate DESC
    ),
    'Not Closed'
  ) AS LastCloseReason,
  SUBSTRING(pwd.Tags, 2, CHARINDEX('>', pwd.Tags) - 2) AS FirstTag
FROM UserContributions AS uc
LEFT JOIN PostWithDetails AS pwd
  ON uc.UserId = pwd.OwnerUserId
WHERE
  uc.TotalPosts > 5 -- Users with at least 5 posts to filter out noise
GROUP BY
  uc.UserId,
  uc.DisplayName,
  uc.Reputation,
  uc.UserCreationDate,
  uc.TotalPosts,
  uc.GoldBadges,
  uc.TotalCommentScore,
  pwd.PostTypeId,
  pwd.Tags -- Group by tags to potentially analyze tag specific contributions if needed in further steps
HAVING
  COUNT(CASE WHEN pwd.PostTypeId = 1 THEN pwd.PostId END) > 0 -- Only include users who have asked questions
ORDER BY
  uc.Reputation DESC,
  uc.TotalPosts DESC
LIMIT 100;
