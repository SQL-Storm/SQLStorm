-- {"query": "36065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 395} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COUNT(DISTINCT v.Id) AS TotalVotes,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  AVG(COALESCE(p.Score,0)) OVER () AS AvgPostScore,
  COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) AS CommentCount,
  MAX(th.CreationDate) AS LastActivityDate,
  string_agg(DISTINCT t.TagName, ',') AS Tags
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN PostHistory th ON th.PostId = p.Id
  LEFT JOIN LATERAL (
    SELECT
      t2.TagName
    FROM
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t2
  ) AS t ON TRUE
WHERE
  p.PostTypeId IN (1,2,5) -- include Questions and Answers and certain tag-wiki types
  AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY
  p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, u.DisplayName
ORDER BY
  TotalVotes DESC, LastActivityDate DESC
LIMIT 100;