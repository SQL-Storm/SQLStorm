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
    FROM Posts p
    JOIN PostTypes pt
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
        FROM Posts p_inner
        WHERE
          p_inner.OwnerUserId = u.Id
      ) AS TotalPosts,
      (
        SELECT
          COUNT(DISTINCT b.Id)
        FROM Badges b
        WHERE
          b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadges,
      (
        SELECT
          SUM(p_comments.Score)
        FROM Posts p_outer
        JOIN Comments p_comments
          ON p_outer.Id = p_comments.PostId
        WHERE
          p_outer.OwnerUserId = u.Id
      ) AS TotalCommentScore
    FROM Users u
    WHERE
      u.Id IN (
        SELECT DISTINCT OwnerUserId
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
      )
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
      -- Use standard SQL for date difference: extract epoch days if needed; here using DATE_PART for portability (Postgres)
      -- If not Postgres, replace with appropriate function; keep as days difference via (LastActivityDate - CreationDate)
      CAST(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400 AS INTEGER) AS PostActivityDurationDays,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN COALESCE(p.FavoriteCount,0) > 100 THEN 'Popular'
        WHEN COALESCE(p.Score,0) > 10 THEN 'Highly Rated'
        ELSE 'Regular'
      END AS PostStatusCategory
    FROM Posts p
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId IN (1, 2)
  ),
  LastCloseReasons AS (
    SELECT
      ph.PostId,
      ph.Comment,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
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
  COALESCE(lcr.Comment, 'Not Closed') AS LastCloseReason,
  -- safe extraction of first tag: handle NULLs
  CASE
    WHEN pwd.Tags IS NOT NULL AND POSITION('>' IN pwd.Tags) > 0 THEN SUBSTRING(pwd.Tags FROM 2 FOR (POSITION('>' IN pwd.Tags) - 2))
    ELSE NULL
  END AS FirstTag
FROM UserContributions uc
LEFT JOIN PostWithDetails pwd
  ON uc.UserId = pwd.OwnerUserId
LEFT JOIN LastCloseReasons lcr
  ON lcr.PostId = pwd.PostId AND lcr.rn = 1
WHERE
  uc.TotalPosts > 5
GROUP BY
  uc.UserId,
  uc.DisplayName,
  uc.Reputation,
  uc.UserCreationDate,
  uc.TotalPosts,
  uc.GoldBadges,
  uc.TotalCommentScore,
  -- Must group by any non-aggregated columns from joined tables that appear in select
  lcr.Comment,
  pwd.Tags
HAVING
  COUNT(CASE WHEN pwd.PostTypeId = 1 THEN pwd.PostId END) > 0
ORDER BY
  uc.Reputation DESC,
  uc.TotalPosts DESC
LIMIT 100;