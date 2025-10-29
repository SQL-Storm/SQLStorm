-- {"query": "4492.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 977} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.Score > 10 AND p.AnswerCount < 5
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(p.Id) AS TotalPosts,
      AVG(p.Score) AS AvgPostScore,
      MAX(p.CreationDate) AS LatestPostDate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  CommentAnalysis AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS NumberOfComments,
      AVG(c.Score) AS AvgCommentScore,
      SUM(CASE WHEN c.UserDisplayName IS NULL THEN 1 ELSE 0 END) AS AnonymousComments
    FROM Comments AS c
    GROUP BY
      c.PostId
  ),
  PostWithAnalysis AS (
    SELECT
      rp.PostId,
      rp.Title,
      rp.PostTypeName,
      rp.Score,
      rp.AnswerCount,
      rp.CommentCount,
      ca.NumberOfComments,
      ca.AvgCommentScore,
      ca.AnonymousComments,
      COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
      COALESCE(ups.AvgPostScore, 0) AS UserAvgPostScore,
      CASE
        WHEN rp.Score > 50 THEN 'High Score'
        WHEN rp.Score BETWEEN 10 AND 50 THEN 'Medium Score'
        ELSE 'Low Score'
      END AS ScoreCategory,
      CASE
        WHEN rp.CreationDate < DATE('now', '-1 year') THEN 'Old'
        ELSE 'Recent'
      END AS AgeCategory,
      CASE
        WHEN rp.OwnerUserId = -1 THEN 'Community'
        ELSE ups.DisplayName
      END AS OwnerDisplayName
    FROM RankedPosts AS rp
    LEFT JOIN CommentAnalysis AS ca
      ON rp.PostId = ca.PostId
    LEFT JOIN UserPostStats AS ups
      ON rp.OwnerUserId = ups.UserId
    WHERE
      rp.rn <= 10
  )
SELECT
  pwa.PostId,
  pwa.Title,
  pwa.PostTypeName,
  pwa.Score,
  pwa.AnswerCount,
  pwa.CommentCount,
  pwa.NumberOfComments,
  pwa.AvgCommentScore,
  pwa.AnonymousComments,
  pwa.UserTotalPosts,
  pwa.UserAvgPostScore,
  pwa.ScoreCategory,
  pwa.AgeCategory,
  pwa.OwnerDisplayName,
  UPPER(SUBSTR(pwa.Title, 1, 3)) || '-' || LOWER(REPLACE(pwa.OwnerDisplayName, ' ', '_')) AS DerivedIdentifier
FROM PostWithAnalysis AS pwa
WHERE
  pwa.AvgCommentScore > 0 OR pwa.AnonymousComments > 3
UNION
SELECT
  rp.Id,
  rp.Title,
  pt.Name,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  NULL,
  NULL,
  NULL,
  0,
  0.0,
  'N/A',
  'N/A',
  'Unknown',
  'NO_DERIVED_IDENTIFIER'
FROM Posts AS rp
JOIN PostTypes AS pt
  ON rp.PostTypeId = pt.Id
WHERE
  rp.Score < 0 AND rp.ViewCount > 1000 AND rp.OwnerUserId IS NULL
ORDER BY
  pwa.Score DESC NULLS LAST,
  pwa.NumberOfComments DESC;
