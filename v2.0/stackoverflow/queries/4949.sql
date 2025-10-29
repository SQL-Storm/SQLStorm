WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.Title AS PostTitle,
    p.AnswerCount,
    pt.Name AS PostTypeName,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_desc,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ASC) AS rn_asc,
    LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore,
    LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextPostScore,
    SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalViews
  FROM Posts p
  JOIN PostTypes pt
    ON p.PostTypeId = pt.Id
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId IN (1, 2)
), CommentCounts AS (
  SELECT
    PostId,
    COUNT(Id) AS NumComments
  FROM Comments
  GROUP BY
    PostId
), UserPostActivity AS (
  SELECT
    OwnerUserId AS UserId,
    COUNT(Id) AS TotalPosts,
    SUM(Score) AS TotalScore
  FROM Posts
  WHERE
    OwnerUserId IS NOT NULL AND OwnerUserId <> -1
  GROUP BY
    OwnerUserId
), RecentHighScoringQuestions AS (
  SELECT
    Id,
    Title,
    Score,
    AnswerCount,
    ViewCount,
    OwnerUserId
  FROM Posts
  WHERE
    PostTypeId = 1
    AND CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    AND Score > 100
    AND AnswerCount > 5
), QuestionTagAnalysis AS (
  SELECT
    p.Id AS QuestionId,
    p.Title AS QuestionTitle,
    p.OwnerUserId,
    t.TagName,
    CASE
      WHEN REPLACE(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>', '') LIKE '%' || t.TagName || '%' THEN 1
      ELSE 0
    END AS TagInTitle,
    CASE
      WHEN POSITION(t.TagName IN REPLACE(REPLACE(REPLACE(p.Tags, '><', ','), '<', ''), '>', '')) > 0 THEN 1
      ELSE 0
    END AS TagInTagsColumn
  FROM Posts p
  CROSS JOIN Tags t
  WHERE
    p.PostTypeId = 1
    AND t.TagName IN ('sql', 'performance', 'query', 'optimization', 'database')
), UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS QuestionsAnswered,
    SUM(CASE WHEN c.UserId = u.Id THEN 1 ELSE 0 END) AS CommentsMade,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c
    ON u.Id = c.UserId
  WHERE
    u.Reputation > 5000
  GROUP BY
    u.Id,
    u.DisplayName
  HAVING
    COUNT(DISTINCT p.Id) > 10 OR SUM(CASE WHEN c.UserId = u.Id THEN 1 ELSE 0 END) > 20
), NullOrEmptyPosts AS (
  SELECT
    Id,
    PostTypeId,
    CASE
      WHEN Title IS NULL OR Title = '' THEN 'No Title'
      WHEN Body IS NULL OR Body = '' THEN 'No Body'
      ELSE 'Complete'
    END AS ContentStatus
  FROM Posts
  WHERE
    Title IS NULL OR Title = '' OR Body IS NULL OR Body = ''
)
SELECT
  rp.PostId,
  rp.PostTypeId,
  rp.PostTypeName,
  rp.PostTitle,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.PostScore,
  rp.AnswerCount,
  cc.NumComments,
  rp.PreviousPostScore,
  rp.NextPostScore,
  rp.RunningTotalViews,
  COALESCE(upa.TotalPosts, 0) AS UserTotalPosts,
  COALESCE(upa.TotalScore, 0) AS UserTotalScore,
  CASE WHEN rsq.Id IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsRecentHighScoring,
  qta.TagName,
  qta.TagInTitle,
  qta.TagInTagsColumn,
  ue.QuestionsAnswered,
  ue.CommentsMade,
  ue.LastPostDate,
  nop.ContentStatus,
  rp.PostCreationDate
FROM RankedPosts rp
LEFT JOIN CommentCounts cc
  ON rp.PostId = cc.PostId
LEFT JOIN UserPostActivity upa
  ON rp.OwnerUserId = upa.UserId
LEFT JOIN RecentHighScoringQuestions rsq
  ON rp.PostId = rsq.Id
LEFT JOIN QuestionTagAnalysis qta
  ON rp.PostId = qta.QuestionId
LEFT JOIN UserEngagement ue
  ON rp.OwnerUserId = ue.UserId
LEFT JOIN NullOrEmptyPosts nop
  ON rp.PostId = nop.Id
WHERE
  rp.rn_desc BETWEEN 1 AND 50
  AND (qta.TagName IS NOT NULL OR ue.UserId IS NOT NULL OR nop.Id IS NOT NULL)
GROUP BY
  rp.PostId,
  rp.PostTypeId,
  rp.PostTypeName,
  rp.PostTitle,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.PostScore,
  rp.AnswerCount,
  cc.NumComments,
  rp.PreviousPostScore,
  rp.NextPostScore,
  rp.RunningTotalViews,
  upa.TotalPosts,
  upa.TotalScore,
  rsq.Id,
  qta.TagName,
  qta.TagInTitle,
  qta.TagInTagsColumn,
  ue.QuestionsAnswered,
  ue.CommentsMade,
  ue.LastPostDate,
  nop.ContentStatus,
  rp.PostCreationDate
ORDER BY
  rp.PostTypeId,
  rp.PostCreationDate DESC;