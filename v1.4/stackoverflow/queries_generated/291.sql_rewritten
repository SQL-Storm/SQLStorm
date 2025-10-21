-- {"query": "291.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 7507} 
WITH
  tagged_posts AS (
    SELECT p.Id AS PostId,
           p.OwnerUserId,
           p.Score,
           p.ViewCount,
           p.CreationDate,
           t.tag AS Tag
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(tag)
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
  ),
  tag_stats AS (
    SELECT
      tp.Tag,
      COUNT(*) AS QCount,
      AVG(p.Score) AS AvgScore,
      SUM(p.ViewCount) AS TotalViews,
      AVG(EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - p.CreationDate)) / 86400) AS AvgAgeDays,
      AVG(u.Reputation) AS AvgUserRep,
      MAX(u.Reputation) AS MaxUserRep,
      COUNT(DISTINCT tp.OwnerUserId) AS DistOwners
    FROM tagged_posts tp
    LEFT JOIN Posts p ON p.Id = tp.PostId
    LEFT JOIN Users u ON tp.OwnerUserId = u.Id
    GROUP BY tp.Tag
  ),
  user_stats AS (
    SELECT
      COALESCE(u.DisplayName, 'Community') AS Key,
      COUNT(p.Id) AS PostCount,
      AVG(p.Score) AS AvgPostScore,
      SUM(p.ViewCount) AS TotalViews
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    GROUP BY COALESCE(u.DisplayName, 'Community')
  )
SELECT
  'TagStats' AS SourceType,
  ts.Tag AS Key,
  ts.QCount AS A,
  ts.AvgScore AS B,
  ts.TotalViews AS C,
  ts.AvgAgeDays AS D,
  ts.AvgUserRep AS E,
  ts.MaxUserRep AS F,
  ts.DistOwners AS G,
  NULL AS H,
  NULL AS I,
  NULL AS J
FROM tag_stats ts
UNION ALL
SELECT
  'UserStats' AS SourceType,
  us.Key AS Key,
  us.PostCount AS A,
  us.AvgPostScore AS B,
  us.TotalViews AS C,
  NULL AS D,
  NULL AS E,
  NULL AS F,
  NULL AS G,
  NULL AS H,
  NULL AS I,
  NULL AS J
FROM user_stats us
ORDER BY SourceType, Key
LIMIT 100;