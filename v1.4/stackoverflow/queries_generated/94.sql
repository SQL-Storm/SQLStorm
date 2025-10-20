-- {"query": "94.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 847} 
WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TagPopularity AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS TotalScore,
    COUNT(*) AS QuestionCount
  FROM Posts p
  JOIN LATERAL unnest(string_to_array(REPLACE(p.Tags, '<',''), '>')) AS tag_name ON true
  LEFT JOIN Tags t ON t.TagName = unnest(string_to_array(REPLACE(p.Tags, '<',''), '>'))
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopScoringQuestions AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    r.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY r.Score DESC, r.ViewCount DESC, r.LastActivityDate DESC) AS overall_rank
  FROM RecentTopQuestions r
  WHERE r.rn = 1
),
ComplexBenchmark AS (
  SELECT
    t.TagName,
    t.TotalScore,
    t.QuestionCount,
    a.UserId,
    a.DisplayName AS UserDisplayName,
    a.Reputation,
    q.PostId AS QuestionId,
    q.Title AS QuestionTitle,
    q.CreationDate AS QuestionCreationDate,
    q.LastActivityDate AS QuestionLastActivityDate,
    q.ViewCount AS QuestionViews,
    q.Score AS QuestionScore,
    STRING_AGG(DISTINCT cl.Name, ',') AS ClosedReasons
  FROM TagPopularity t
  LEFT JOIN LATERAL (
    SELECT p.Id AS PostId, p.Title, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%' || t.TagName || '%'
      AND p.ClosedDate IS NULL
    ORDER BY p.Score DESC
    LIMIT 1
  ) q ON true
  LEFT JOIN Users a ON a.Id = q.OwnerUserId
  LEFT JOIN PostHistory ph ON ph.PostId = q.PostId AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes cl ON cl.Id = CAST(JSON_VALUE(ph.Comment, '$.closeReasonId') AS int)
  GROUP BY t.TagName, t.TotalScore, t.QuestionCount, a.UserId, a.DisplayName, a.Reputation, q.PostId, q.Title, q.CreationDate, q.LastActivityDate, q.ViewCount, q.Score
)
SELECT
  c.TagName,
  c.TotalScore,
  c.QuestionCount,
  c.UserDisplayName,
  c.Reputation,
  c.QuestionId,
  c.QuestionTitle,
  c.QuestionCreationDate,
  c.QuestionLastActivityDate,
  c.QuestionViews,
  c.QuestionScore,
  c.ClosedReasons,
  u.ActivityRank
FROM ComplexBenchmark c
JOIN (
  SELECT UserId, ROW_NUMBER() OVER (ORDER BY Reputation DESC, LastActive DESC) AS ActivityRank
  FROM UserActivity
) u ON u.UserId = c.UserId
ORDER BY c.TotalScore DESC
LIMIT 50;