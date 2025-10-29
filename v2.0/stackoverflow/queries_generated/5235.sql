-- {"query": "5235.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 775} 
WITH
RecentActiveQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id AS PostId
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) s
  JOIN Tags t ON t.TagName = s.TagName
  JOIN Posts p ON p.Id = s.PostId
  GROUP BY t.TagName
),
TopContributions AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS QCount,
    SUM(p.ViewCount) AS TotalViewsByUser,
    AVG(p.Score) AS AvgPostScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(DISTINCT p.Id) > 0
),
PerformanceMetrics AS (
  SELECT
    -- number of questions with at least one answer
    SUM(CASE WHEN a.Id IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAnswer,
    -- average answer-to-question ratio per question
    AVG(CASE WHEN a.Id IS NOT NULL THEN 1.0 ELSE 0.0 END) AS AvgAnswerPerQuestion,
    -- total comments on questions and answers
    (SELECT COUNT(*) FROM Comments c JOIN Posts pq ON pq.Id = c.PostId WHERE pq.PostTypeId IN (1,2)) AS TotalComments,
    -- distinct users who edited posts in last 30 days
    (SELECT COUNT(DISTINCT UserId) FROM PostHistory ph WHERE ph.CreationDate >= NOW() - INTERVAL '30 days') AS EditorsLast30Days
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
)
SELECT
  r.PostId,
  r.Title AS QuestionTitle,
  r.Tags,
  r.CreationDate AS QuestionCreated,
  r.LastActivityDate AS LastActive,
  r.Score AS QuestionScore,
  r.ViewCount AS QuestionViews,
  r.OwnerDisplayName AS Author,
  COALESCE(tc.TagName, 'untagged') AS TopTag,
  tc.TagCount,
  tc.AvgScore AS TopTagAvgScore,
  tc.TotalViews AS TopTagTotalViews,
  cu.QCount AS ContributorQuestions,
  cu.Reputation AS ContributorReputation,
  cu.TotalViewsByUser AS ContributorTotalViews,
  cu.AvgPostScore AS ContributorAvgScore,
  pm.QuestionsWithAnswer,
  pm.AvgAnswerPerQuestion,
  pm.TotalComments,
  pm.EditorsLast30Days
FROM RecentActiveQuestions r
LEFT JOIN TopTags tc ON true
LEFT JOIN TopContributions cu ON true
CROSS JOIN PerformanceMetrics pm
ORDER BY r.LastActivityDate DESC
LIMIT 100;