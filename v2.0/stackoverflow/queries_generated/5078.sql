-- {"query": "5078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 408} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  MAX(p.CreationDate) AS MostRecentPost,
  MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId = 2) AS MostRecentUpVoteOnPost,
  ARRAY_AGG(DISTINCT t.Name) FILTER (WHERE t.Name IS NOT NULL) AS TagNames,
  COALESCE(NULLIF(u.Location, ''), 'Unknown') AS LocationGroup,
  CASE
    WHEN u.Reputation >= 20000 THEN 'Legendary'
    WHEN u.Reputation >= 1000 THEN 'Pro'
    WHEN u.Reputation >= 100 THEN 'Established'
    ELSE 'New'
  END AS ReputationTier,
  COUNT(*) OVER () AS TotalRows
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(p.Tags, '>'))
  ) AS t_name ON TRUE
  LEFT JOIN Tags t ON t.TagName = REPLACE(REPLACE(TRIM(BOTH '>< ' FROM p.Tags), '<', ''), '>', '')
WHERE
  p.Id IS NULL
  OR p.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.Location
HAVING
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 0
ORDER BY
  Reputation DESC,
  MostRecentPost DESC
LIMIT 100;