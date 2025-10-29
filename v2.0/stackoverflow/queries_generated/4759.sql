-- {"query": "4759.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1165} 

WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate AS PostCreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts AS p
  LEFT JOIN Users AS u
    ON p.OwnerUserId = u.Id
  WHERE
    p.Title IS NOT NULL AND u.DisplayName IS NOT NULL AND p.OwnerUserId > 0
), QuestionsByPopularity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    q.AnswerCount,
    q.FavoriteCount,
    q.CommentCount,
    q.Score AS QuestionScore,
    CASE
      WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
      ELSE 'Open'
    END AS QuestionStatus,
    CASE
      WHEN u.Reputation > 100000 THEN 'High Rep'
      WHEN u.Reputation > 50000 THEN 'Medium-High Rep'
      WHEN u.Reputation > 10000 THEN 'Medium Rep'
      WHEN u.Reputation > 1000 THEN 'Low-Medium Rep'
      ELSE 'Low Rep'
    END AS OwnerReputationTier
  FROM RankedPosts AS rp
  JOIN Posts AS q
    ON rp.PostId = q.Id
  JOIN Users AS u
    ON q.OwnerUserId = u.Id
  WHERE
    rp.rn <= 100 AND q.PostTypeId = 1 AND q.AnswerCount IS NOT NULL
), HighRatedAnswers AS (
  SELECT
    a.ParentId AS QuestionId,
    COUNT(a.Id) AS HighRatedAnswerCount,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(a.CreationDate) AS LatestAnswerDate
  FROM Posts AS a
  WHERE
    a.PostTypeId = 2 AND a.Score > 5
  GROUP BY
    a.ParentId
)
SELECT
  qbp.Title AS QuestionTitle,
  qbp.OwnerDisplayName AS QuestionOwner,
  qbp.PostCreationDate AS QuestionDate,
  qbp.QuestionStatus,
  qbp.OwnerReputationTier,
  COALESCE(hra.HighRatedAnswerCount, 0) AS NumberOfHighRatedAnswers,
  COALESCE(hra.AvgAnswerScore, 0) AS AverageHighRatedAnswerScore,
  CASE
    WHEN qbp.QuestionScore > 50 THEN 'Very High Score'
    WHEN qbp.QuestionScore > 20 THEN 'High Score'
    ELSE 'Moderate Score'
  END AS QuestionScoreCategory,
  COALESCE(
    (
      SELECT
        COUNT(c.Id)
      FROM Comments AS c
      WHERE
        c.PostId = qbp.PostId AND c.Score > 3 AND LENGTH(c.Text) > 100
    ),
    0
  ) AS SignificantCommentCount,
  UPPER(SUBSTRING(qbp.OwnerDisplayName FROM 1 FOR 3)) AS OwnerDisplayNameInitials,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = qbp.PostId AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate Of'
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.RelatedPostId = qbp.PostId AND pl.LinkTypeId = 3
    ) THEN 'Has Duplicates'
    ELSE 'No Direct Duplicates'
  END AS DuplicateStatus,
  CASE
    WHEN qbp.FavoriteCount > 10 THEN 'Highly Favorited'
    WHEN qbp.FavoriteCount > 0 THEN 'Favorited'
    ELSE 'Not Favorited'
  END AS FavoriteStatus,
  qbp.AnswerCount AS TotalAnswerCount,
  CASE
    WHEN qbp.AnswerCount > qbp.CommentCount THEN 'More Answers Than Comments'
    WHEN qbp.AnswerCount < qbp.CommentCount THEN 'More Comments Than Answers'
    ELSE 'Equal Answers and Comments'
  END AS AnswerCommentRatio,
  (
    SELECT
      COUNT(ph.Id)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = qbp.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS EditHistoryCount,
  (
    SELECT
      MIN(pht.CreationDate)
    FROM PostHistory AS pht
    WHERE
      pht.PostId = qbp.PostId AND pht.PostHistoryTypeId = 10
  ) AS FirstCloseDate,
  hra.LatestAnswerDate
FROM QuestionsByPopularity AS qbp
LEFT JOIN HighRatedAnswers AS hra
  ON qbp.PostId = hra.QuestionId
ORDER BY
  qbp.PostCreationDate DESC
LIMIT 50;
