-- {"query": "5569.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 795}
WITH
RecentQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90' DAY
),
TopTags AS (
  SELECT
    s.TagName,
    SUM(CASE WHEN s.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionCount,
    AVG(s.Score) AS AvgScore,
    MAX(s.ViewCount) AS MaxViews
  FROM (
    SELECT
      unnest(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), '><')) AS TagName,
      p.Id,
      p.OwnerUserId,
      p.Score,
      p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90' DAY
  ) AS s
  JOIN Tags t ON t.TagName = s.TagName
  GROUP BY s.TagName
  ORDER BY QuestionCount DESC
  LIMIT 20
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT q.Id) AS QCountLast90,
    SUM(q.ViewCount) AS TotalViewsLast90,
    AVG(q.Score) AS AvgQuestionScore
  FROM Users u
  LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1 AND q.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90' DAY
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Aggregate AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.LastActivityDate,
    t.Name AS PostTypeName,
    w.TotalViewsLast90
  FROM RecentQuestions r
  LEFT JOIN PostTypes t ON t.Id = 1
  LEFT JOIN UserActivity w ON w.UserId = r.OwnerUserId
),
ComplexMetrics AS (
  SELECT
    a.PostId,
    a.Title,
    a.Tags,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    a.OwnerUserId,
    a.LastActivityDate,
    a.PostTypeName,
    a.TotalViewsLast90,
    -- Correlated subquery: count of comments on the post with non-null user
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.PostId AND c.UserId IS NOT NULL) AS Commenters,
    -- Window function over recent activity: rank posts by LastActivityDate per owner
    ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.LastActivityDate DESC) AS OwnerPostRank
  FROM Aggregate a
)
SELECT
  cm.PostId,
  cm.Title,
  cm.Tags,
  cm.CreationDate,
  cm.Score,
  cm.ViewCount,
  cm.OwnerUserId,
  cm.LastActivityDate,
  cm.PostTypeName,
  cm.TotalViewsLast90,
  cm.Commenters,
  cm.OwnerPostRank,
  (cm.Score * 2 + cm.ViewCount * 0.5 + cm.Commenters * 3) AS EngagementScore
FROM ComplexMetrics cm
LEFT JOIN TopTags tt ON true
WHERE
  cm.TotalViewsLast90 IS NOT NULL
  OR cm.Commenters > 0
ORDER BY EngagementScore DESC
LIMIT 100;