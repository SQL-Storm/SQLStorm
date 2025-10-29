-- {"query": "4077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1275} 

WITH
  RankedPosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      p.AnswerCount,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
      DENSE_RANK() OVER (ORDER BY p.CommentCount DESC) as CommentRank,
      LAG(p.FavoriteCount, 1, 0) OVER (ORDER BY p.CreationDate) as PreviousFavoriteCount,
      LEAD(p.FavoriteCount, 1, 0) OVER (ORDER BY p.CreationDate) as NextFavoriteCount,
      CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.AnswerCount > 0 THEN CAST(p.AnswerCount AS REAL) / p.FavoriteCount ELSE 0 END AS AnswerToFavoriteRatio,
      ROW_NUMBER() OVER (ORDER BY p.Id) as RowNum
    FROM Posts AS p
    WHERE
      p.PostTypeId IN (1, 2) AND p.Score > 0 AND p.OwnerUserId IS NOT NULL AND p.CreationDate > '2023-01-01'
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    WHERE
      p.PostTypeId = 1 AND p.CreationDate > '2023-01-01'
    GROUP BY
      u.Id
  ),
  HotQuestions AS (
    SELECT
      PostId,
      COUNT(*) AS VoteCount
    FROM Votes AS v
    WHERE
      v.VoteTypeId = 2 AND v.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY
      PostId
    HAVING
      COUNT(*) > 100
  )
SELECT
  rp.Id AS PostId,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  rp.Score,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.AnswerCount,
  rp.CreationDate,
  rp.ScoreRank,
  rp.CommentRank,
  rp.PreviousFavoriteCount,
  rp.NextFavoriteCount,
  rp.AnswerToFavoriteRatio,
  COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
  COALESCE(ups.TotalScore, 0) AS UserTotalScore,
  COALESCE(ups.AvgScore, 0.0) AS UserAvgScore,
  CASE WHEN hq.PostId IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsHotQuestion,
  'Post' || rp.Id || '-' || COALESCE(u.DisplayName, 'Unknown') AS PostIdentifier,
  rp.RowNum,
  CASE
    WHEN rp.Score > 500 AND rp.CommentCount > 50 THEN 'High Engagement'
    WHEN rp.Score < 0 THEN 'Negative Score'
    WHEN rp.AnswerCount = 0 THEN 'No Answers'
    ELSE 'Standard'
  END AS EngagementLevel,
  LENGTH(rp.OwnerUserId::TEXT) AS OwnerUserIdLength
FROM RankedPosts AS rp
LEFT OUTER JOIN PostTypes AS pt
  ON rp.PostTypeId = pt.Id
LEFT OUTER JOIN Users AS u
  ON rp.OwnerUserId = u.Id
LEFT OUTER JOIN UserPostStats AS ups
  ON rp.OwnerUserId = ups.UserId
LEFT OUTER JOIN HotQuestions AS hq
  ON rp.Id = hq.PostId
WHERE
  rp.ScoreRank <= 100
  AND rp.CommentRank <= 50
  AND rp.AnswerToFavoriteRatio > 0.1
  AND rp.CreationDate < NOW() - INTERVAL '1 day'
  AND u.Location IS NOT NULL
  AND UPPER(u.DisplayName) LIKE '%A%'
UNION ALL
SELECT
  p.Id,
  pt.Name,
  u.DisplayName,
  p.Score,
  p.CommentCount,
  p.FavoriteCount,
  p.AnswerCount,
  p.CreationDate,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  ups.TotalPosts,
  ups.TotalScore,
  ups.AvgScore,
  NULL,
  'Comment' || c.Id || '-' || COALESCE(u.DisplayName, 'Unknown'),
  ROW_NUMBER() OVER (ORDER BY p.Id) as RowNum,
  NULL,
  LENGTH(p.OwnerUserId::TEXT)
FROM Posts AS p
JOIN Comments AS c
  ON p.Id = c.PostId
JOIN Users AS u
  ON c.UserId = u.Id
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN UserPostStats AS ups
  ON c.UserId = ups.UserId
WHERE
  c.Score > 10 AND c.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
  AND ups.TotalScore > 10000;
