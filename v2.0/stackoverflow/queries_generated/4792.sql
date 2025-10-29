-- {"query": "4792.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1226} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      pht.Name AS HistoryType,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      COUNT(DISTINCT a.Id) AS AnswerCount,
      SUM(CASE WHEN c.UserId = u.Id THEN 1 ELSE 0 END) AS CommentCount,
      SUM(CASE WHEN b.UserId = u.Id THEN 1 ELSE 0 END) AS BadgeCount,
      AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0.0 END) AS AvgUpvoteRate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 -- Questions
    LEFT JOIN Posts AS a
      ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 -- Answers
    LEFT JOIN Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  )
SELECT
  p.Id AS PostId,
  p.Title,
  pt.Name AS PostType,
  u.DisplayName AS OwnerDisplayName,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  COALESCE(p.CommunityOwnedDate, '2000-01-01') AS CommunityOwnedDate, -- Handle NULL by providing a default
  uc.QuestionCount AS OwnerTotalQuestions,
  uc.AnswerCount AS OwnerTotalAnswers,
  uc.CommentCount AS OwnerTotalComments,
  uc.BadgeCount AS OwnerTotalBadges,
  CONCAT(rpe.CreationDate, ' by ', rpe.HistoryType) AS LatestEditInfo,
  CASE
    WHEN p.Score > 100 AND p.AnswerCount > 10 THEN 'High Performing'
    WHEN p.Score <= 0 AND p.ClosedDate IS NOT NULL THEN 'Closed and Low Score'
    WHEN p.ViewCount > 10000 AND p.FavoriteCount IS NULL THEN 'Popular but Not Favorited'
    ELSE 'Standard'
  END AS PerformanceCategory,
  CASE
    WHEN uc.AvgUpvoteRate > 0.6 THEN 'High Quality Contributor'
    WHEN uc.AvgUpvoteRate < 0.2 THEN 'Needs Improvement'
    ELSE 'Average Contributor'
  END AS ContributorQuality
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserContribution AS uc
  ON u.Id = uc.UserId
LEFT JOIN RankedPostEdits AS rpe
  ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE
  p.Score > -5
  AND (
    p.Title LIKE '%performance%'
    OR p.Body ILIKE '%performance%'
  )
  AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
UNION
SELECT
  NULL AS PostId,
  'Summary' AS Title,
  'Analysis' AS PostType,
  NULL AS OwnerDisplayName,
  NULL AS CreationDate,
  AVG(p.Score) AS Score,
  SUM(p.ViewCount) AS ViewCount,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
  COUNT(DISTINCT c.Id) AS CommentCount,
  SUM(p.FavoriteCount) AS FavoriteCount,
  NULL AS ClosedDate,
  NULL AS CommunityOwnedDate,
  AVG(uc.QuestionCount) AS OwnerTotalQuestions,
  AVG(uc.AnswerCount) AS OwnerTotalAnswers,
  AVG(uc.CommentCount) AS OwnerTotalComments,
  SUM(uc.BadgeCount) AS OwnerTotalBadges,
  NULL AS LatestEditInfo,
  'Overall Average' AS PerformanceCategory,
  'Overall Average' AS ContributorQuality
FROM Posts AS p
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
LEFT JOIN UserContribution AS uc
  ON u.Id = uc.UserId
LEFT JOIN Comments AS c
  ON p.Id = c.PostId
WHERE
  p.PostTypeId = 1 -- Only consider questions for this summary
  AND p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31';
