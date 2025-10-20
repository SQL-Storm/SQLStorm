-- {"query": "179.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2685} 
WITH recent AS (
  SELECT p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  u.Id AS user_id,
  u.DisplayName,
  u.Reputation,
  COUNT(r.Id) FILTER (WHERE r.CreationDate >= now() - INTERVAL '365 days') AS questions_last_year,
  AVG(r.Score) FILTER (WHERE r.CreationDate >= now() - INTERVAL '365 days') AS avg_score_last_year,
  (SELECT STRING_AGG(tag, ',')
     FROM (
       SELECT unnest(string_to_array(substr(t.Tags, 2, length(t.Tags) - 2), '><')) AS tag
       FROM Posts t
       WHERE t.OwnerUserId = u.Id AND t.PostTypeId = 1
     ) s
  ) AS top_tags_of_user
FROM Users u
LEFT JOIN recent r ON r.OwnerUserId = u.Id
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY u.Reputation DESC, top_tags_of_user
LIMIT 100;