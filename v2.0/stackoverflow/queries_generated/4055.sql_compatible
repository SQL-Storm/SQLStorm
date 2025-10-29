WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.Score > 100 AND p.CreationDate > DATE '2023-01-01'
  ),
  UserPostActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS NumQuestions,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumAnswers,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AvgPostScore,
      MAX(p.CreationDate) AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    WHERE
      u.Reputation > 5000
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  CommentAnalysis AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS NumComments,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments,
      AVG(CAST(c.Score AS DOUBLE PRECISION)) AS AvgCommentScore,
      MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE
      c.CreationDate > DATE '2023-06-01'
    GROUP BY
      c.PostId
  ),
  PostDetails AS (
    SELECT
      p.Id,
      p.Title,
      p.Tags,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.AnswerCount = 0 THEN 'No Answers'
        WHEN p.FavoriteCount > 100 THEN 'Popular'
        ELSE 'Active'
      END AS PostStatus,
      COALESCE(ca.NumComments, 0) AS TotalComments,
      COALESCE(ca.PositiveComments, 0) AS PosComments
    FROM Posts p
    LEFT JOIN CommentAnalysis ca
      ON p.Id = ca.PostId
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  )
SELECT
  pd.Id AS PostID,
  pd.Title AS PostTitle,
  pd.PostStatus,
  upa.DisplayName AS OwnerDisplayName,
  upa.NumQuestions,
  upa.NumAnswers,
  upa.AvgPostScore,
  pd.Score AS PostScore,
  pd.TotalComments,
  pd.PosComments,
  pd.FavoriteCount,
  pd.ClosedDate,
  CASE
    WHEN pd.OwnerUserId = (
      SELECT OwnerUserId FROM Posts WHERE Id = pd.Id
    ) THEN 'Primary Owner'
    ELSE 'Other'
  END AS OwnerType,
  -- extract first tag between '<' and '>' assuming tags like '<tag1><tag2>'
  CASE
    WHEN pd.Tags IS NULL THEN NULL
    WHEN POSITION('>' IN SUBSTRING(pd.Tags FROM 2)) > 0
      THEN SUBSTRING(pd.Tags FROM 2 FOR POSITION('>' IN SUBSTRING(pd.Tags FROM 2)) - 1)
    ELSE NULL
  END AS FirstTag,
  CASE
    WHEN RANK() OVER (ORDER BY pd.Score DESC) <= 10 THEN 'Top 10'
    WHEN RANK() OVER (ORDER BY pd.Score DESC) BETWEEN 11 AND 50 THEN 'Top 50'
    ELSE 'Others'
  END AS ScoreRank,
  upa.LatestPostDate,
  CAST(pd.PosComments AS DOUBLE PRECISION) / NULLIF(CAST(pd.TotalComments AS DOUBLE PRECISION), 0) AS PositiveCommentRatio
FROM PostDetails pd
JOIN UserPostActivity upa
  ON pd.OwnerUserId = upa.UserId
WHERE
  (pd.Score > 50 OR pd.TotalComments > 20)
  AND pd.OwnerUserId IS NOT NULL

UNION

SELECT
  rp.PostId,
  rp.Title,
  rp.PostTypeName AS PostStatus,
  NULL AS OwnerDisplayName,
  NULL AS NumQuestions,
  NULL AS NumAnswers,
  NULL AS AvgPostScore,
  rp.Score AS PostScore,
  NULL AS TotalComments,
  NULL AS PosComments,
  NULL AS FavoriteCount,
  NULL AS ClosedDate,
  'System/Community' AS OwnerType,
  NULL AS FirstTag,
  'Top 1000' AS ScoreRank,
  rp.CreationDate AS LatestPostDate,
  NULL AS PositiveCommentRatio
FROM RankedPosts rp
WHERE
  rp.rn <= 1000

ORDER BY
  PostScore DESC,
  OwnerDisplayName NULLS FIRST;