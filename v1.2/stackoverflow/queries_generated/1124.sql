-- {"query": "1124.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1450} 

WITH RecursiveTagHierarchy AS (
  SELECT t.Id, t.TagName, t.Count, p.Title, p.CreationDate,
         p.ViewCount, p.Score,
         ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC, p.CreationDate) AS TagRank
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE p.PostTypeId = 1
  UNION ALL
  SELECT t2.Id, t2.TagName, t2.Count, p2.Title, p2.CreationDate,
         p2.ViewCount, p2.Score,
         ROW_NUMBER() OVER (PARTITION BY t2.TagName ORDER BY p2.Score DESC, p2.CreationDate)
  FROM Tags t2
  JOIN Posts p2 ON p2.Id = t2.WikiPostId
  WHERE p2.PostTypeId = 1
),
UserBadgeStats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) AS GoldBadges,
         COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id ELSE NULL END) AS SilverBadges,
         COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id ELSE NULL END) AS BronzeBadges,
         COALESCE(u.Reputation,0) AS Reputation,
         RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopAnswersPerQuestion AS (
  SELECT a.ParentId AS QuestionId, a.Id AS AnswerId, a.Score,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank,
         u.DisplayName AS AnswerOwner,
         COALESCE(a.Body, '') AS AnswerBodySnippet
  FROM Posts a
  LEFT JOIN Users u ON a.OwnerUserId = u.Id
  WHERE a.PostTypeId = 2 AND a.Score >= 0
),
CloseReasonUsage AS (
  SELECT cr.Id AS CloseReasonId, cr.Name AS CloseReasonName,
         COUNT(ph.Id) AS TotalClosures
  FROM CloseReasonTypes cr
  LEFT JOIN PostHistory ph ON ph.PostHistoryTypeId = 10 AND ph.Comment = CAST(cr.Id AS VARCHAR)
  GROUP BY cr.Id, cr.Name
),
QuestionsWithComplexFilters AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags,
         us.DisplayName AS OwnerDisplay,
         us.GoldBadges, us.SilverBadges, us.BronzeBadges, us.Reputation,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveCommentsCount,
         (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.BountyAmount IS NOT NULL) AS AvgBountyAmount,
         ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS QuestionRank
  FROM Posts p
  LEFT JOIN UserBadgeStats us ON p.OwnerUserId = us.UserId
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND (p.Score > 10 OR p.FavoriteCount > 5)
    AND ((p.Tags IS NOT NULL AND p.Tags LIKE '%<python>%') OR p.Tags LIKE '%<sql>%')
),
QuestionsAndTopAnswers AS (
  SELECT q.Id AS QuestionId, q.Title AS QuestionTitle, q.CreationDate AS QuestionCreated,
         q.Score AS QuestionScore, q.ViewCount AS QuestionViews, q.Tags,
         ta.AnswerId, ta.Score AS AnswerScore, ta.AnswerOwner,
         qs.GoldBadges, qs.SilverBadges, qs.BronzeBadges, qs.Reputation,
         qs.PositiveCommentsCount, COALESCE(qs.AvgBountyAmount, 0) AS AvgBounty
  FROM QuestionsWithComplexFilters q
  LEFT JOIN TopAnswersPerQuestion ta ON ta.QuestionId = q.Id AND ta.AnswerRank = 1
  LEFT JOIN UserBadgeStats qs ON qs.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = q.Id)
),
FinalResult AS (
  SELECT qta.QuestionId,
         qta.QuestionTitle,
         qta.QuestionCreated,
         qta.QuestionScore,
         qta.QuestionViews,
         qta.Tags,
         qta.AnswerId,
         qta.AnswerScore,
         qta.AnswerOwner,
         qta.GoldBadges,
         qta.SilverBadges,
         qta.BronzeBadges,
         qta.Reputation,
         qta.PositiveCommentsCount,
         qta.AvgBounty,
         cr.CloseReasonName,
         CASE
           WHEN qta.AnswerScore IS NULL THEN 'No Answer'
           WHEN qta.AnswerScore > qta.QuestionScore THEN 'Answer Outscored Question'
           ELSE 'Answer Did Not Outscore Question'
         END AS AnswerScoreComparison,
         CONCAT('User#', qta.AnswerOwner, COALESCE(' (Rep: ' || qta.Reputation || ')', '')) AS AnswererInfo,
         LENGTH(COALESCE((SELECT Body FROM Posts WHERE Id = qta.AnswerId), '')) AS AnswerBodyLength
  FROM QuestionsAndTopAnswers qta
  LEFT JOIN PostHistory ph ON ph.PostId = qta.QuestionId AND ph.PostHistoryTypeId = 10 -- Post Closed events
  LEFT JOIN CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS SMALLINT)
  WHERE qta.QuestionScore > 15 OR qta.AnswerScore > 10
  ORDER BY qta.QuestionScore DESC, qta.AnswerScore DESC
  LIMIT 100
)

SELECT *
FROM FinalResult

UNION

SELECT
  p.Id AS QuestionId,
  p.Title AS QuestionTitle,
  p.CreationDate AS QuestionCreated,
  p.Score AS QuestionScore,
  p.ViewCount AS QuestionViews,
  p.Tags,
  NULL AS AnswerId,
  NULL AS AnswerScore,
  NULL AS AnswerOwner,
  0 AS GoldBadges,
  0 AS SilverBadges,
  0 AS BronzeBadges,
  0 AS Reputation,
  0 AS PositiveCommentsCount,
  0 AS AvgBounty,
  NULL AS CloseReasonName,
  'No Answer' AS AnswerScoreComparison,
  NULL AS AnswererInfo,
  0 AS AnswerBodyLength
FROM Posts p
WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.Score < 0
ORDER BY p.Score ASC
LIMIT 10;
