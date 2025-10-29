-- {"query": "5651.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 300} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserDisplayName,
  COUNT(DISTINCT p.Id) AS TotalPostsOwned,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  MAX(p.LastActivityDate) AS LastActivity,
  COUNT(DISTINCT b.Id) AS BadgesEarned,
  STRING_AGG(DISTINCT t.Name, ',') AS TopTagsEarned
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Tags t ON t.Id IN (
  SELECT
    CASE
      WHEN p.Tags LIKE '%<' || t.TagName || '>%'
      THEN t.Id
      ELSE NULL
    END
  FROM Posts p2
  JOIN Tags t ON t.IsModeratorOnly = 0
  WHERE p2.OwnerUserId = u.Id
  LIMIT 1
)
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalPostsOwned DESC, LastActivity DESC
LIMIT 100;