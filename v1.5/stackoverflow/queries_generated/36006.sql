-- {"query": "36006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 179} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
  MAX(p.CreationDate) AS LatestPostDate,
  STRING_AGG(DISTINCT t.Name, ',') AS TagsUsed
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
    SELECT t.Name
    FROM unnest(string_to_array(p.Tags, '><')) AS t
  ) AS t ON TRUE
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  TotalViews DESC, AvgPostScore DESC
LIMIT 100;