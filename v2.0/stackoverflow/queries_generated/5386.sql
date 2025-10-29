-- {"query": "5386.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 371} 
SELECT
  up.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(*) AS TotalPosts,
  SUM(p.Score) AS SumScore,
  AVG(p.Score) AS AvgScore,
  MAX(p.LastActivityDate) AS LastActive,
  MIN(p.CreationDate) AS CreatedEarliest,
  STRING_AGG(DISTINCT vvt.Name, ',') FILTER (WHERE vtt.Name = 'UpMod') AS UpvotesByType,
  CASE
    WHEN SUM(CASE WHEN v.Name = 'Helpful' THEN 1 ELSE 0 END) > 0 THEN SUM(CASE WHEN v.Name = 'Helpful' THEN 1 ELSE 0 END)
    ELSE 0
  END AS HelpfulVotes
FROM
  Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (SELECT Id, Name FROM VoteTypes) vtt ON 1=1
  LEFT JOIN (SELECT PostId, VoteTypeId, UserId, CreationDate, Name
             FROM Votes v
             JOIN (SELECT Id, Name FROM VoteTypes) vt ON v.VoteTypeId = vt.Id) v ON p.Id = v.PostId
  LEFT JOIN (SELECT Id, Name FROM VoteTypes) vvt ON v.VoteTypeId = vvt.Id
  LEFT JOIN (SELECT Name, Id FROM Users) up ON up.Id = p.OwnerUserId
WHERE
  p.PostTypeId = 1 -- questions
  AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
  up.OwnerUserId,
  u.DisplayName
HAVING
  COUNT(*) > 0
ORDER BY
  TotalPosts DESC,
  LastActive DESC
LIMIT 100;