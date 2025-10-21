-- {"query": "23028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1429} 

WITH TopUsers AS (
  SELECT Id, Reputation, DisplayName, CreationDate,
         ROW_NUMBER() OVER (ORDER BY Reputation DESC NULLS LAST) AS UserRank,
         COALESCE(WebsiteUrl, 'No Website') AS UserWebsite
  FROM Users
  WHERE Reputation > 1000
  ORDER BY Reputation DESC
  LIMIT 50
),
UserPosts AS (
  SELECT tu.Id AS UserId, p.Id AS PostId, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate,
         COALESCE(p.Title, CONCAT('Untitled ', p.PostTypeId)) AS AdjustedTitle,
         NULLIF(p.Tags, '') AS PostTags,
         CASE 
           WHEN p.Score > 10 THEN 'High Score'
           WHEN p.Score BETWEEN 1 AND 10 THEN 'Medium Score'
           ELSE COALESCE('Low Score', NULLIF('Zero Score', CAST(p.Score AS VARCHAR)))
         END AS ScoreCategory,
         LAG(p.Score, 1, 0) OVER (PARTITION BY tu.Id ORDER BY p.CreationDate) AS PreviousScore,
         LEAD(p.ViewCount) OVER (PARTITION BY tu.Id ORDER BY p.CreationDate DESC) AS NextViewCount
  FROM TopUsers tu
  LEFT OUTER JOIN Posts p ON p.OwnerUserId = tu.Id AND p.CreationDate >= tu.CreationDate
  WHERE p.PostTypeId IN (1, 2) OR p.PostTypeId IS NULL
),
BadgeSummary AS (
  SELECT b.UserId, COUNT(DISTINCT b.Name) AS UniqueBadges,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         STRING_AGG(UPPER(b.Name), '; ' ORDER BY b.Date DESC) AS BadgeList
  FROM Badges b
  WHERE EXISTS (SELECT 1 FROM TopUsers tu WHERE tu.Id = b.UserId)
  GROUP BY b.UserId
  HAVING COUNT(*) > 5
),
VoteAnalysis AS (
  SELECT v.PostId, AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) AS AvgBounty,
         COUNT(*) FILTER (WHERE v.VoteTypeId IN (2, 3)) AS NetVotes,
         MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
),
ComplexMetrics AS (
  SELECT up.UserId, up.PostId, up.ScoreCategory, bs.UniqueBadges, va.AvgBounty,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = up.PostId AND c.Score > (SELECT AVG(Score) FROM Comments WHERE PostId = up.PostId)) AS HighScoreComments,  -- correlated subquery
         COALESCE(va.NetVotes, 0) + up.Score AS TotalPoints,
         RANK() OVER (PARTITION BY up.UserId ORDER BY up.CreationDate DESC, va.LastVoteDate) AS ActivityRank
  FROM UserPosts up
  FULL OUTER JOIN BadgeSummary bs ON bs.UserId = up.UserId
  LEFT JOIN VoteAnalysis va ON va.PostId = up.PostId
  WHERE up.AdjustedTitle LIKE '%SQL%' OR (up.PostTags IS NOT NULL AND LENGTH(up.PostTags) > 10)
),
QuestionSet AS (
  SELECT UserId, COUNT(PostId) AS QuestionCount, AVG(TotalPoints) AS AvgQuestionPoints
  FROM ComplexMetrics
  WHERE ScoreCategory != 'Low Score'
  GROUP BY UserId
),
AnswerSet AS (
  SELECT UserId, COUNT(PostId) AS AnswerCount, SUM(TotalPoints) AS TotalAnswerPoints
  FROM ComplexMetrics
  WHERE ActivityRank <= 10
  GROUP BY UserId
)
SELECT tu.DisplayName, tu.UserRank, tu.UserWebsite, cm.ScoreCategory, cm.BadgeList,
       COALESCE(qs.QuestionCount, 0) AS Questions, COALESCE(ans.AnswerCount, 0) AS Answers,
       (qs.AvgQuestionPoints + ans.TotalAnswerPoints) / NULLIF(cm.UniqueBadges, 0) AS PerformanceMetric,
       STRING_AGG(cm.AdjustedTitle, ' | ') AS PostTitles
FROM TopUsers tu
INNER JOIN ComplexMetrics cm ON cm.UserId = tu.Id
LEFT JOIN QuestionSet qs ON qs.UserId = tu.Id
LEFT JOIN AnswerSet ans ON ans.UserId = tu.Id
WHERE tu.UserRank <= 10 OR EXISTS (SELECT 1 FROM UserPosts up WHERE up.UserId = tu.Id AND up.PreviousScore < up.Score)
GROUP BY tu.DisplayName, tu.UserRank, tu.UserWebsite, cm.ScoreCategory, cm.BadgeList, qs.QuestionCount, ans.AnswerCount, qs.AvgQuestionPoints, ans.TotalAnswerPoints, cm.UniqueBadges
UNION ALL
SELECT 'Summary' AS DisplayName, NULL AS UserRank, NULL AS UserWebsite, NULL AS ScoreCategory, NULL AS BadgeList,
       SUM(Questions) AS Questions, SUM(Answers) AS Answers, AVG(PerformanceMetric) AS PerformanceMetric, NULL AS PostTitles
FROM (
  SELECT tu.DisplayName, tu.UserRank, tu.UserWebsite, cm.ScoreCategory, cm.BadgeList,
         COALESCE(qs.QuestionCount, 0) AS Questions, COALESCE(ans.AnswerCount, 0) AS Answers,
         (qs.AvgQuestionPoints + ans.TotalAnswerPoints) / NULLIF(cm.UniqueBadges, 0) AS PerformanceMetric
  FROM TopUsers tu
  INNER JOIN ComplexMetrics cm ON cm.UserId = tu.Id
  LEFT JOIN QuestionSet qs ON qs.UserId = tu.Id
  LEFT JOIN AnswerSet ans ON ans.UserId = tu.Id
  WHERE tu.UserRank > 10
) AS SubSummary
INTERSECT
SELECT tu.DisplayName, tu.UserRank, tu.UserWebsite, cm.ScoreCategory, cm.BadgeList,
       COALESCE(qs.QuestionCount, 0) AS Questions, COALESCE(ans.AnswerCount, 0) AS Answers,
       (qs.AvgQuestionPoints + ans.TotalAnswerPoints) / NULLIF(cm.UniqueBadges, 0) AS PerformanceMetric,
       STRING_AGG(cm.AdjustedTitle, ' | ') AS PostTitles
FROM TopUsers tu
INNER JOIN ComplexMetrics cm ON cm.UserId = tu.Id
LEFT JOIN QuestionSet qs ON qs.UserId = tu.Id
LEFT JOIN AnswerSet ans ON ans.UserId = tu.Id
WHERE cm.AvgBounty > 50 AND cm.HighScoreComments > 0
GROUP BY tu.DisplayName, tu.UserRank, tu.UserWebsite, cm.ScoreCategory, cm.BadgeList, qs.QuestionCount, ans.AnswerCount, qs.AvgQuestionPoints, ans.TotalAnswerPoints, cm.UniqueBadges
ORDER BY UserRank ASC NULLS LAST, PerformanceMetric DESC;
