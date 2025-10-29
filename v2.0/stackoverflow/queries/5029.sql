-- {"query": "5029.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 359}
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgScorePerPost,
  MAX(p.LastActivityDate) AS LastActive,
  STRING_AGG(DISTINCT t.TagName, ',') AS TagNames,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  SUM(CASE WHEN bv.Name IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN (
    SELECT DISTINCT TagName, Id AS TagId
    FROM Tags
  ) t ON POSITION('<' || t.TagName || '>' IN COALESCE(p.Tags, '')) > 0
  LEFT JOIN Badges bv ON bv.UserId = u.Id
WHERE
  u.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years'
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 10
ORDER BY
  PostCount DESC, LastActive DESC
LIMIT 100;