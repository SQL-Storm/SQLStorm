-- {"query": "5839.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 365} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  MAX(p.CreationDate) AS LastPostDate,
  COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
  COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
  STRING_AGG(DISTINCT t.Name, ',') AS TagsUsed,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(p.Tags, '> <')) AS tag
  ) AS t ON true
WHERE
  u.CreationDate >= TIMESTAMP '2020-01-01 00:00:00'
  AND u.Reputation > 100
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  AVG(p.Score) DESC,
  MAX(p.LastActivityDate) DESC
LIMIT 100;