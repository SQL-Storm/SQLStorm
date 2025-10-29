WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_creation,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS dr_by_score
    FROM
      Posts p
      JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId IN (1, 2)
  ),
  UserPostActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserDisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(rp.PostId) AS TotalPosts,
      SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(rp.PostScore) AS AvgPostScore,
      SUM(rp.PostViewCount) AS TotalPostViews,
      MAX(rp.PostCreationDate) AS LastPostDate
    FROM
      Users u
      LEFT JOIN RankedPosts rp
        ON u.Id = rp.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  CommentAnalysis AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate,
      SUM(CASE WHEN c.UserDisplayName IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount
    FROM
      Comments c
    GROUP BY
      c.PostId
  ),
  PostAggregates AS (
    SELECT
      rp.PostId,
      rp.OwnerUserId,
      rp.PostTypeName,
      rp.Title,
      rp.PostCreationDate,
      rp.PostScore,
      rp.PostViewCount,
      rp.AnswerCount,
      COALESCE(ca.CommentCount, 0) AS TotalComments,
      COALESCE(ca.AvgCommentScore, 0) AS AvgCommentsScore,
      CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
      CASE WHEN rp.Title LIKE '%[%]%' THEN 'Contains Brackets' ELSE 'No Brackets' END AS TitleBracketStatus,
      rp.dr_by_score,
      rp.rn_by_creation,
      rp.PostTypeId
    FROM
      RankedPosts rp
      LEFT JOIN CommentAnalysis ca
        ON rp.PostId = ca.PostId
    WHERE
      rp.rn_by_creation <= 1000
  )
SELECT
  pa.PostId,
  pa.PostTypeName,
  pa.Title,
  pa.PostCreationDate,
  pa.PostScore,
  pa.PostViewCount,
  pa.AnswerCount,
  pa.TotalComments,
  pa.AvgCommentsScore,
  pa.PostStatus,
  pa.TitleBracketStatus,
  upa.UserDisplayName,
  upa.Reputation,
  upa.UserCreationDate,
  upa.QuestionCount,
  upa.AnswerCount AS UserAnswerCount,
  upa.AvgPostScore AS UserAvgPostScore,
  upa.TotalPostViews AS UserTotalPostViews,
  CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - upa.LastPostDate)) / 86400 AS INTEGER) AS DaysSinceLastPost,
  pa.dr_by_score
FROM
  PostAggregates pa
  JOIN UserPostActivity upa
    ON pa.OwnerUserId = upa.UserId
WHERE
  pa.PostScore > 50
  AND pa.TotalComments < 100
  AND upa.Reputation > 10000
  AND pa.PostTypeName <> 'TagWikiExcerpt'

UNION

SELECT
  rp.PostId AS PostId,
  rp.PostTypeName AS PostTypeName,
  rp.Title,
  rp.PostCreationDate AS PostCreationDate,
  rp.PostScore AS PostScore,
  rp.PostViewCount AS PostViewCount,
  rp.AnswerCount,
  NULL AS TotalComments,
  NULL AS AvgCommentsScore,
  CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
  CASE WHEN rp.Title LIKE '%[%]%' THEN 'Contains Brackets' ELSE 'No Brackets' END AS TitleBracketStatus,
  NULL AS UserDisplayName,
  NULL AS Reputation,
  NULL AS UserCreationDate,
  NULL AS QuestionCount,
  NULL AS UserAnswerCount,
  NULL AS UserAvgPostScore,
  NULL AS UserTotalPostViews,
  NULL AS DaysSinceLastPost,
  rp.dr_by_score
FROM
  RankedPosts rp
WHERE
  rp.OwnerUserId IS NULL
  AND rp.PostTypeId = 1
  AND rp.PostScore > 100
  AND rp.PostTypeName = 'Question'
ORDER BY
  dr_by_score;