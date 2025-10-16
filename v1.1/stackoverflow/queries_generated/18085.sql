-- {"query": "18085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1392} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.Score DESC,
          p.CreationDate DESC
      ) AS ScoreRank,
      DENSE_RANK() OVER (
        ORDER BY
          p.ViewCount DESC
      ) AS GlobalViewRank,
      AVG(p.Score) OVER (
        PARTITION BY
          p.PostTypeId
      ) AS AvgScoreForPostType
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.Score > 0
      AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  ),
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS TotalPosts,
      SUM(CASE WHEN Score > 10 THEN 1 ELSE 0 END) AS HighScorePosts
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COALESCE(upc.TotalPosts, 0) AS TotalPostsByUser,
      COALESCE(upc.HighScorePosts, 0) AS HighScorePostsByUser,
      CASE
        WHEN AVG(rp.Score) OVER (PARTITION BY u.Id) IS NULL THEN 0
        ELSE ROUND(AVG(rp.Score) OVER (PARTITION BY u.Id), 2)
      END AS AvgPostScore,
      MAX(rp.CreationDate) OVER (PARTITION BY u.Id) AS LatestPostDate,
      COUNT(rp.PostId) FILTER (
        WHERE
          rp.ScoreRank <= 5
      ) AS Top5ScoringPostsCount
    FROM
      Users AS u
    LEFT JOIN
      RankedPosts AS rp
      ON u.Id = rp.OwnerUserId
    LEFT JOIN
      UserPostCounts AS upc
      ON u.Id = upc.OwnerUserId
    WHERE
      u.Id BETWEEN 1000 AND 20000
    GROUP BY
      u.Id,
      u.DisplayName,
      upc.TotalPosts,
      upc.HighScorePosts
  ),
  PostContributions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      COUNT(c.Id) AS CommentCountOnPost,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount
    FROM
      Posts AS p
    LEFT JOIN
      Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 1 -- Questions only
    GROUP BY
      p.Id,
      p.OwnerUserId
  )
SELECT
  ups.UserId,
  ups.DisplayName,
  ups.TotalPostsByUser,
  ups.HighScorePostsByUser,
  ups.AvgPostScore,
  ups.LatestPostDate,
  ups.Top5ScoringPostsCount,
  rp.Title AS TopScoringPostTitle,
  rp.Score AS TopScoringPostScore,
  rp.GlobalViewRank,
  pc.CommentCountOnPost,
  pc.PositiveCommentCount,
  CASE
    WHEN ups.AvgPostScore > 50 THEN 'High Performer'
    WHEN ups.AvgPostScore > 10 THEN 'Moderate Performer'
    ELSE 'Low Performer'
  END AS PerformanceCategory,
  CASE
    WHEN ups.LatestPostDate < NOW() - INTERVAL '1 year' THEN 'Inactive'
    ELSE 'Active'
  END AS ActivityStatus,
  CASE
    WHEN pc.CommentCountOnPost > 100 AND pc.PositiveCommentCount > 75 THEN 'Highly Engaged'
    ELSE 'Standard Engagement'
  END AS EngagementLevel
FROM
  UserPostStats AS ups
LEFT JOIN
  RankedPosts AS rp
  ON ups.UserId = rp.OwnerUserId AND rp.ScoreRank = 1
LEFT JOIN
  PostContributions AS pc
  ON ups.UserId = pc.OwnerUserId
WHERE
  ups.TotalPostsByUser >= 10
  AND ups.AvgPostScore > 5
UNION
SELECT
  ups.UserId,
  ups.DisplayName,
  ups.TotalPostsByUser,
  ups.HighScorePostsByUser,
  ups.AvgPostScore,
  ups.LatestPostDate,
  ups.Top5ScoringPostsCount,
  rp.Title AS TopScoringPostTitle,
  rp.Score AS TopScoringPostScore,
  rp.GlobalViewRank,
  pc.CommentCountOnPost,
  pc.PositiveCommentCount,
  CASE
    WHEN ups.AvgPostScore > 50 THEN 'High Performer'
    WHEN ups.AvgPostScore > 10 THEN 'Moderate Performer'
    ELSE 'Low Performer'
  END AS PerformanceCategory,
  CASE
    WHEN ups.LatestPostDate < NOW() - INTERVAL '1 year' THEN 'Inactive'
    ELSE 'Active'
  END AS ActivityStatus,
  CASE
    WHEN pc.CommentCountOnPost > 100 AND pc.PositiveCommentCount > 75 THEN 'Highly Engaged'
    ELSE 'Standard Engagement'
  END AS EngagementLevel
FROM
  UserPostStats AS ups
JOIN
  RankedPosts AS rp
  ON ups.UserId = rp.OwnerUserId AND rp.ScoreRank = 1
JOIN
  PostContributions AS pc
  ON ups.UserId = pc.OwnerUserId
WHERE
  ups.TotalPostsByUser < 10
  AND ups.AvgPostScore <= 5
ORDER BY
  ups.UserId;
