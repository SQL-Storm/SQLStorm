-- {"query": "5623.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 410} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActive,
  STRING_AGG(DISTINCT t.Name, ',') AS TagsUsed,
  COUNT(DISTINCT pb.Id) AS BadgesEarned,
  MAX(v.CreationDate) AS LastVoteDate,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN Tags t ON t.Id = COALESCE(NULLIF(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), ''), t.Id)
LEFT JOIN Badges pb ON pb.UserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
WHERE
  u.Reputation > 1000
  AND u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
  AND (p.PostTypeId IN (1,2) OR p.PostTypeId IS NULL)
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  Reputation DESC, LastActive DESC
LIMIT 100;