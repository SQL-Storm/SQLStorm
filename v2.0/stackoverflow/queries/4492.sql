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
    FROM Posts p
    JOIN PostTypes pt
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
    FROM Users u
    LEFT JOIN Posts p
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
    FROM Comments c
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
        WHEN rp.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Old'
        ELSE 'Recent'
      END AS AgeCategory,
      CASE
        WHEN rp.OwnerUserId = -1 THEN 'Community'
        ELSE ups.DisplayName
      END AS OwnerDisplayName,
      rp.rn
    FROM RankedPosts rp
    LEFT JOIN CommentAnalysis ca
      ON rp.PostId = ca.PostId
    LEFT JOIN UserPostStats ups
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
  UPPER(SUBSTRING(pwa.Title FROM 1 FOR 3)) || '-' || LOWER(REPLACE(pwa.OwnerDisplayName, ' ', '_')) AS DerivedIdentifier
FROM PostWithAnalysis pwa
WHERE
  (pwa.AvgCommentScore IS NOT NULL AND pwa.AvgCommentScore > 0)
  OR COALESCE(pwa.AnonymousComments, 0) > 3

UNION

SELECT
  rp.Id,
  rp.Title,
  pt.Name,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  NULL AS NumberOfComments,
  NULL AS AvgCommentScore,
  NULL AS AnonymousComments,
  0 AS UserTotalPosts,
  0.0 AS UserAvgPostScore,
  'N/A' AS ScoreCategory,
  'N/A' AS AgeCategory,
  'Unknown' AS OwnerDisplayName,
  'NO_DERIVED_IDENTIFIER' AS DerivedIdentifier
FROM Posts rp
JOIN PostTypes pt
  ON rp.PostTypeId = pt.Id
WHERE
  rp.Score < 0 AND rp.ViewCount > 1000 AND rp.OwnerUserId IS NULL

ORDER BY
  Score DESC NULLS LAST,
  NumberOfComments DESC;