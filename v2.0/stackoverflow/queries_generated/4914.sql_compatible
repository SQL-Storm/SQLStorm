WITH RankedPostEdits AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.CreationDate,
    ph.Comment,
    pht.Name AS HistoryTypeName,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  JOIN PostHistoryTypes pht
    ON ph.PostHistoryTypeId = pht.Id
  WHERE
    ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
),
UserPostActivity AS (
  SELECT
    p.OwnerUserId,
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
  FROM Posts p
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  WHERE
    p.OwnerUserId IS NOT NULL AND p.PostTypeId = 1
),
QuestionInteractions AS (
  SELECT
    q.Id AS PostId,
    COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
    COUNT(DISTINCT a.Id) AS AnswerCountOnQuestion,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCountOnQuestion,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCountOnQuestion,
    COUNT(DISTINCT pl.Id) AS LinkCountFromQuestion
  FROM Posts q
  LEFT JOIN Comments c
    ON q.Id = c.PostId
  LEFT JOIN Posts a
    ON q.Id = a.ParentId
  LEFT JOIN Votes v
    ON q.Id = v.PostId
  LEFT JOIN PostLinks pl
    ON q.Id = pl.PostId
  WHERE
    q.PostTypeId = 1
  GROUP BY
    q.Id
)
SELECT
  upa.OwnerDisplayName,
  upa.PostId,
  upa.PostCreationDate,
  upa.PostScore,
  upa.AnswerCount,
  upa.CommentCount,
  upa.FavoriteCount,
  upa.ClosedDate,
  upa.Reputation,
  COALESCE(rpe.HistoryTypeName, 'No Edits') AS LatestEditType,
  CASE
    WHEN rpe.rn = 1 AND rpe.UserId IS NOT NULL THEN 'Has Recent Edit'
    ELSE 'No Recent Edit'
  END AS HasRecentEditIndicator,
  CASE
    WHEN upa.UserPostRank <= 5 THEN 'Top 5 Posts'
    ELSE 'Other Posts'
  END AS UserActivityTier,
  qi.CommentCountOnQuestion,
  qi.AnswerCountOnQuestion,
  qi.UpvoteCountOnQuestion,
  qi.DownvoteCountOnQuestion,
  qi.LinkCountFromQuestion,
  CASE
    WHEN qi.CommentCountOnQuestion > 100 AND qi.AnswerCountOnQuestion < 10 THEN 'High Engagement, Low Answers'
    WHEN qi.UpvoteCountOnQuestion > qi.DownvoteCountOnQuestion * 5 THEN 'Strong Positive Sentiment'
    WHEN upa.ClosedDate IS NOT NULL THEN 'Closed Question'
    ELSE 'Open Question'
  END AS QuestionStatusCategory,
  UPPER(SUBSTRING(upa.OwnerDisplayName FROM 1 FOR 3)) AS DisplayNameAbbreviation,
  LENGTH(upa.OwnerDisplayName) AS DisplayNameLength,
  upa.PostScore * (upa.AnswerCount + 1) AS ScoreAnswerProduct,
  CASE
    WHEN upa.PostScore IS NULL OR upa.AnswerCount IS NULL OR upa.FavoriteCount IS NULL THEN 'Incomplete Data'
    ELSE CAST(upa.PostScore + upa.AnswerCount + upa.FavoriteCount AS VARCHAR)
  END AS CompositeScore,
  CASE
    WHEN upa.PostCreationDate BETWEEN DATE_TRUNC('year', CAST('2024-10-01' AS DATE)) AND CAST('2024-10-01' AS DATE) THEN 'Current Year'
    ELSE 'Previous Years'
  END AS CreationYearCategory
FROM UserPostActivity upa
LEFT JOIN RankedPostEdits rpe
  ON upa.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN QuestionInteractions qi
  ON upa.PostId = qi.PostId
WHERE
  upa.PostScore > 10 OR upa.AnswerCount > 5 OR upa.FavoriteCount > 10
UNION
SELECT
  upa.OwnerDisplayName,
  upa.PostId,
  upa.PostCreationDate,
  upa.PostScore,
  upa.AnswerCount,
  upa.CommentCount,
  upa.FavoriteCount,
  upa.ClosedDate,
  upa.Reputation,
  COALESCE(rpe.HistoryTypeName, 'No Edits') AS LatestEditType,
  CASE
    WHEN rpe.rn = 1 AND rpe.UserId IS NOT NULL THEN 'Has Recent Edit'
    ELSE 'No Recent Edit'
  END AS HasRecentEditIndicator,
  CASE
    WHEN upa.UserPostRank <= 5 THEN 'Top 5 Posts'
    ELSE 'Other Posts'
  END AS UserActivityTier,
  qi.CommentCountOnQuestion,
  qi.AnswerCountOnQuestion,
  qi.UpvoteCountOnQuestion,
  qi.DownvoteCountOnQuestion,
  qi.LinkCountFromQuestion,
  CASE
    WHEN qi.CommentCountOnQuestion > 100 AND qi.AnswerCountOnQuestion < 10 THEN 'High Engagement, Low Answers'
    WHEN qi.UpvoteCountOnQuestion > qi.DownvoteCountOnQuestion * 5 THEN 'Strong Positive Sentiment'
    WHEN upa.ClosedDate IS NOT NULL THEN 'Closed Question'
    ELSE 'Open Question'
  END AS QuestionStatusCategory,
  UPPER(SUBSTRING(upa.OwnerDisplayName FROM 1 FOR 3)) AS DisplayNameAbbreviation,
  LENGTH(upa.OwnerDisplayName) AS DisplayNameLength,
  upa.PostScore * (upa.AnswerCount + 1) AS ScoreAnswerProduct,
  CASE
    WHEN upa.PostScore IS NULL OR upa.AnswerCount IS NULL OR upa.FavoriteCount IS NULL THEN 'Incomplete Data'
    ELSE CAST(upa.PostScore + upa.AnswerCount + upa.FavoriteCount AS VARCHAR)
  END AS CompositeScore,
  CASE
    WHEN upa.PostCreationDate BETWEEN DATE_TRUNC('year', CAST('2024-10-01' AS DATE)) AND CAST('2024-10-01' AS DATE) THEN 'Current Year'
    ELSE 'Previous Years'
  END AS CreationYearCategory
FROM UserPostActivity upa
JOIN RankedPostEdits rpe
  ON upa.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN QuestionInteractions qi
  ON upa.PostId = qi.PostId
WHERE
  rpe.HistoryTypeName IS NOT NULL AND upa.PostScore < 5 AND upa.AnswerCount < 2;