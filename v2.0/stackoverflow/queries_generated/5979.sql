-- {"query": "5979.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 382} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(p.Id) AS PostsCreated,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
  MAX(p.CreationDate) OVER (PARTITION BY u.Id) AS LastActive,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN p.Id END) AS UpvotesReceived,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN p.Id END) AS DownvotesReceived,
  STRING_AGG(DISTINCT t.Name, ',') AS TagSet,
  MIN(CASE WHEN p.OwnerUserId IS NULL THEN 1 ELSE 0 END) AS HasOrphanedPosts,
  CASE
    WHEN u.Reputation > 2000 THEN 'High'
    WHEN u.Reputation > 500 THEN 'Medium'
    ELSE 'Low'
  END AS ReputationTier
FROM
  Users u
  LEFT JOIN Posts p
    ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v
    ON v.PostId = p.Id
  LEFT JOIN LATERAL (
      SELECT unnest(string_to_array(p.Tags, '<>')) AS tagname
  ) AS tag_split
    ON true
  LEFT JOIN Tags t
    ON LOWER(t.TagName) = LOWER(tag_split.tagname)
WHERE
  u.AccountId IS NOT NULL
  AND u.LastAccessDate < NOW() -- ensure we consider historically active users
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.AccountId
ORDER BY
  ReputationTier DESC,
  PostsCreated DESC
LIMIT 100;