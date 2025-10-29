-- {"query": "5881.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 625} 
WITH 
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.DisplayName AS OwnerName,
    u.Reputation
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate IS NOT NULL
),
TagGeek AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestions,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Posts p
  JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
       ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
TopContributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(p.Id) >= 5
),
ActivityScore AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.OwnerName,
    ra.Reputation,
    CASE
      WHEN ra.ViewCount > 1000 THEN ra.ViewCount * 2
      ELSE ra.ViewCount
    END AS ScaledViews,
    CASE
      WHEN ra.Score > 0 THEN ra.Score
      ELSE 0
    END AS PositiveScore,
    ROW_NUMBER() OVER (PARTITION BY ra.OwnerUserId ORDER BY ra.LastActivityDate DESC) AS rn
  FROM RecentActivity ra
),
Consolidated AS (
  SELECT
    a.PostId,
    a.Title,
    a.CreationDate,
    a.LastActivityDate,
    a.OwnerName,
    a.Reputation,
    a.ScaledViews,
    a.PositiveScore,
    a.rn,
    t.TagName
  FROM ActivityScore a
  LEFT JOIN UNNEST(ARRAY[SELECT TagName FROM TagGeek WHERE TagQuestions > 0] ) AS t(TagName)
    ON TRUE
)
SELECT
  ca.PostId,
  ca.Title,
  ca.OwnerName,
  ca.Reputation,
  ca.LastActivityDate,
  ca.ScaledViews,
  ca.PositiveScore,
  ca.rn,
  ca.TagName
FROM Consolidated ca
WHERE ca.rn <= 5
ORDER BY ca.LastActivityDate DESC, ca.ScaledViews DESC
LIMIT 100;