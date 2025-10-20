SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.CreationDate) AS LastActive,
  STRING_AGG(DISTINCT tt.Name, ',') AS TopTagsByPosts
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
    SELECT t AS Name
    FROM UNNEST(string_to_array(COALESCE(p.Tags, ''), '<>')) AS t
    GROUP BY t
  ) AS tt ON TRUE
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 50
ORDER BY
  LastActive DESC
LIMIT 100;