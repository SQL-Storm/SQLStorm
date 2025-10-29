-- {"query": "5605.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 337}
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS QuestionCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  AVG(u.Reputation) AS AvgReputation,
  MAX(u.CreationDate) AS FirstSeen,
  STRING_AGG(t.TagName, ',') AS TagPatterns,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswer,
  COALESCE(MAX(p.LastActivityDate), MAX(p.CreationDate)) AS LastActivity
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN (
      SELECT
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags)-2)), '><')) AS TagName
      FROM Posts p
      WHERE p.PostTypeId = 1
  ) t ON t.UserId = u.Id
WHERE
  p.CreationDate IS NOT NULL
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  LastActivity DESC, UpVotesReceived DESC
LIMIT 100;