-- {"query": "5998.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 653} 
WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.LastActivityDate IS NOT NULL
),
QuestionTagMetrics AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreCount
  FROM RecentActivePosts rap
  CROSS APPLY (
    SELECT 
      unnest(string_to_array(substr(rap.Tags, 2, length(rap.Tags) - 2), '><')) AS TagName
  ) AS tkns
  CROSS APPLY (
    SELECT tkns.TagName
  ) AS t
  INNER JOIN Posts p ON p.Id = rap.PostId
  GROUP BY t.TagName
),
TopContributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(*) AS PostCount,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC, COUNT(*) DESC) AS rn
  FROM RecentActivePosts rap
  INNER JOIN Posts p ON p.Id = rap.PostId
  INNER JOIN Users u ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(*) > 0
)
SELECT
  -- Outer join style: bring in top contributors and their most upvoted questions
  u.UserId,
  u.DisplayName,
  tc.TagName,
  tc.QuestionCount,
  tc.AvgScore,
  tc.MaxViews,
  tc.PositiveScoreCount,
  hc.PostCount,
  hc.TotalScore,
  hc.TotalViews,
  -- Window function: rank top questions per user by LastActivityDate
  ROW_NUMBER() OVER (PARTITION BY u.UserId ORDER BY rap.LastActivityDate DESC) AS UserQuestionRank,
  rap.Title AS QuestionTitle,
  rap.CreationDate AS QuestionCreated,
  rap.LastActivityDate AS QuestionLastActive,
  rap.Score AS QuestionScore,
  rap.ViewCount AS QuestionViews
FROM TopContributors hc
LEFT JOIN Users u ON u.Id = hc.UserId
LEFT JOIN LATERAL (
  SELECT
    rap.PostId,
    rap.Title,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount
  FROM RecentActivePosts rap
  WHERE rap.OwnerUserId = hc.UserId
  ORDER BY rap.LastActivityDate DESC
  LIMIT 5
) rap ON true
LEFT JOIN QuestionTagMetrics tc ON true
ORDER BY hc.TotalScore DESC
LIMIT 100;