-- {"query": "49.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 682} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.AccountId,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
    COUNT(DISTINCT p.Id) AS PostsCount,
    MAX(p.LastActivityDate) AS LastActivity,
    STRING_AGG(DISTINCT CAST(t.Name AS varchar(100)), ',') AS PostTypes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostTypes t ON p.PostTypeId = t.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.AccountId
),
tag_popularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.ExcerptPostId
  JOIN LATERAL (SELECT unnest(string_to_array(p.Tags, '><')) AS tn) AS s ON true
  JOIN (SELECT TagName, Id FROM Tags) AS t ON t.TagName = s.tn
  GROUP BY t.TagName
),
combined AS (
  SELECT
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.CreationDate,
    rua.LastAccessDate,
    rua.AccountId,
    rua.TotalBounty,
    rua.PostsCount,
    rua.LastActivity,
    rua.PostTypes,
    COALESCE(tp.TagCount, 0) AS PopularTagsCount,
    COALESCE(tp.AvgScore, 0) AS AvgPostScore
  FROM recent_user_activity rua
  LEFT JOIN tag_popularity tp ON tp.TagName LIKE '%' || rua.DisplayName || '%'
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.CreationDate,
  c.LastAccessDate,
  c.AccountId,
  c.TotalBounty,
  c.PostsCount,
  c.LastActivity,
  c.PostTypes,
  c.PopularTagsCount,
  c.AvgPostScore,
  ARRAY_AGG(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN p.Id END) FILTER (WHERE p.Id IS NOT NULL) AS UpvotedPostIds,
  ARRAY_AGG(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN p.Id END) FILTER (WHERE p.Id IS NOT NULL) AS DownvotedPostIds
FROM combined c
LEFT JOIN Posts p ON p.OwnerUserId = c.UserId
LEFT JOIN Votes v ON v.PostId = p.Id
GROUP BY
  c.UserId, c.DisplayName, c.Reputation, c.CreationDate, c.LastAccessDate, c.AccountId,
  c.TotalBounty, c.PostsCount, c.LastActivity, c.PostTypes, c.PopularTagsCount, c.AvgPostScore
ORDER BY c.Reputation DESC, c.PostsCount DESC
LIMIT 100;