-- {"query": "5147.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 420}
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActive,
  MAX(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  STRING_AGG(DISTINCT t.Name, ',') FILTER (WHERE p.PostTypeId = 1) AS TagsInQuestions,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
FROM
  Users u
LEFT JOIN
  Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
  Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN LATERAL
  (
    SELECT tag_split.Name
    FROM (
      SELECT TRIM(value) AS Name
      FROM UNNEST(STRING_TO_ARRAY(COALESCE(p.Tags, ''), '<>')) AS value
    ) AS tag_split
    LEFT JOIN Tags tt ON tt.TagName = tag_split.Name
    WHERE p.PostTypeId = 1
  ) t ON TRUE
WHERE
  (u.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
   OR u.LastAccessDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1 year'))
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  u.Reputation DESC,
  MAX(p.LastActivityDate) DESC
LIMIT 100;