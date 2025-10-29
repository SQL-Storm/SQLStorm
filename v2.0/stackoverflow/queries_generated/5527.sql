-- {"query": "5527.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 391} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  COUNT(DISTINCT v.Id) AS VoteCount,
  MAX(p.CreationDate) AS LastPostDate,
  AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgPostScore,
  STRING_AGG(DISTINCT t.Name, ',') AS TopTags
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
    SELECT
      tt.Name
    FROM
      UNNEST(string_to_array(p.Tags, '>')) AS tag
      JOIN Tags t ON t.TagName = REPLACE(REPLACE(tag, '<', ''), '>', '')
    WHERE
      p.Tags IS NOT NULL
    GROUP BY t.Name
    ORDER BY COUNT(*) DESC
    LIMIT 3
  ) AS t_top ON true
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
WHERE
  u.Id IS NOT NULL
  AND (
    p.Id IS NULL
    OR p.PostTypeId IN (1, 2)
  )
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  Reputation DESC, UserName
LIMIT 100;