-- {"query": "5360.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 361} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  MAX(p.LastActivityDate) AS LastActivity,
  AVG(COALESCE(p.Score, 0)) AS AvgScorePerPost,
  STRING_AGG(DISTINCT tt.Name, ',') AS TopCategories
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
    AND v.VoteTypeId IN (2,3) -- up/down votes
  LEFT JOIN (
    SELECT
      pt.Id,
      CASE
        WHEN pt.Id = 1 THEN 'Question'
        WHEN pt.Id = 2 THEN 'Answer'
        ELSE 'Other'
      END AS Name
    FROM PostTypes pt
  ) tt ON tt.Id = p.PostTypeId
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 10
ORDER BY
  TotalPosts DESC, UpVotesReceived DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;