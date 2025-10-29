WITH
  PostAnswerCounts AS (
    SELECT
      p.Id AS PostId,
      COUNT(a.Id) AS AnswerCount
    FROM
      Posts p
    LEFT JOIN
      Posts a ON p.Id = a.ParentId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id
  ),
  UserPostActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT ph.PostId) AS TotalPostsEdited,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 ELSE 0 END) AS TitleEdits,
      MAX(ph.CreationDate) AS LastEditDate
    FROM
      Users u
    JOIN
      PostHistory ph ON u.Id = ph.UserId
    WHERE
      ph.PostHistoryTypeId IN (1, 2, 4, 5, 7, 8)
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.Score,
      p.ViewCount,
      p.FavoriteCount,
      p.AnswerCount,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousQuestionScore,
      ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS RankByViews,
      NULL AS PlaceholderWindowCol,
      CAST(NULL AS TIMESTAMP) AS PlaceholderLastEditDate
    FROM
      Posts p
    LEFT JOIN
      Users u ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
  )
SELECT
  qs.QuestionId,
  qs.Title,
  qs.Score,
  qs.ViewCount,
  qs.FavoriteCount,
  qs.AnswerCount,
  qs.OwnerDisplayName,
  qs.PostStatus,
  qs.PreviousQuestionScore,
  upa.DisplayName AS LastEditorDisplayName,
  upa.Reputation AS LastEditorReputation,
  upa.TotalPostsEdited,
  upa.BodyEdits,
  upa.TitleEdits,
  CAST(EXTRACT(YEAR FROM upa.LastEditDate) AS VARCHAR) || '-' || LPAD(CAST(EXTRACT(MONTH FROM upa.LastEditDate) AS VARCHAR), 2, '0') AS EditMonth,
  COALESCE(pact.AnswerCount, 0) AS ActualAnswerCount,
  CASE
    WHEN qs.RankByViews <= 100 THEN 'Top 100'
    WHEN qs.RankByViews > 100 AND qs.RankByViews <= 500 THEN '101-500'
    ELSE 'Above 500'
  END AS ViewRankGroup,
  (qs.Score * 1.0 / NULLIF(qs.ViewCount, 0)) AS ScorePerViewRatio,
  CASE
    WHEN qs.FavoriteCount > 50 THEN 'High'
    WHEN qs.FavoriteCount > 10 THEN 'Medium'
    ELSE 'Low'
  END AS FavoriteLevel
FROM
  QuestionStats qs
LEFT JOIN
  UserPostActivity upa ON qs.OwnerUserId = upa.UserId
LEFT JOIN
  PostAnswerCounts pact ON qs.QuestionId = pact.PostId
WHERE
  qs.Score > 10
  AND qs.ViewCount > 1000
  AND qs.OwnerDisplayName IS NOT NULL
  AND qs.PostStatus <> 'Closed'
  AND EXTRACT(YEAR FROM upa.LastEditDate) = 2023
UNION ALL
SELECT
  NULL AS QuestionId,
  'Total Posts' AS Title,
  COUNT(DISTINCT p.Id) AS Score,
  SUM(p.ViewCount) AS ViewCount,
  SUM(p.FavoriteCount) AS FavoriteCount,
  NULL AS AnswerCount,
  NULL AS OwnerDisplayName,
  NULL AS PostStatus,
  NULL AS PreviousQuestionScore,
  NULL AS LastEditorDisplayName,
  NULL AS LastEditorReputation,
  NULL AS TotalPostsEdited,
  NULL AS BodyEdits,
  NULL AS TitleEdits,
  NULL AS EditMonth,
  NULL AS ActualAnswerCount,
  NULL AS ViewRankGroup,
  NULL AS ScorePerViewRatio,
  NULL AS FavoriteLevel
FROM
  Posts p
WHERE
  p.PostTypeId = 1;