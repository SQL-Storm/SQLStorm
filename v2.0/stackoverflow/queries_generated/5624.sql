-- {"query": "5624.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 291} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  MAX(p.LastActivityDate) AS LastActive,
  COUNT(DISTINCT b.Id) AS BadgeCount,
  MAX(b.Date) AS MostRecentBadgeDate,
  STRING_AGG(DISTINCT t.Name, ',') AS TopTags
FROM
  Users u
LEFT JOIN
  Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
  Badges b ON b.UserId = u.Id
LEFT JOIN
  Tags t ON t.Id IN (
        SELECT
          UNNEST(string_to_array(REPLACE(p.Tags, '><', '|'), '|'))
        FROM
          Posts p_sub
        WHERE
          p_sub.OwnerUserId = u.Id
        LIMIT 1
      )
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(p.Id) > 5
ORDER BY
  Reputation DESC,
  LastActive DESC
LIMIT 100;