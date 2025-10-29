-- {"query": "5818.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 953} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(SUM(v.BountyAmount),0) AS TotalBounties,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY v.CreationDate DESC) AS rn
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
tag_summary AS (
  SELECT
    t.TagName,
    t.Count,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE t.IsModeratorOnly = 0
),
complex_post_aggregation AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.CommentCount, 0) AS CommentCount,
    p.LastActivityDate,
    jsonb_build_object(
      'Owner', COALESCE(uu.DisplayName, p.OwnerDisplayName),
      'Reputation', COALESCE(uu.Reputation, 0)
    ) AS OwnerInfo
  FROM Posts p
  LEFT JOIN Users uu ON p.OwnerUserId = uu.Id
  WHERE p.PostTypeId IN (1,2)
),
windowed_activity AS (
  SELECT
    cp.*,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY cp.PostId) AS UpvotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY cp.PostId) AS DownvotesForPost,
    ROW_NUMBER() OVER (PARTITION BY cp.PostId ORDER BY p.LastEditDate DESC NULLS LAST) AS rn_post
  FROM complex_post_aggregation cp
  LEFT JOIN Posts p ON p.Id = cp.PostId
  LEFT JOIN Votes v ON v.PostId = cp.PostId
)
SELECT
  w.PostId,
  w.Title,
  w.PostTypeId,
  w.Score,
  w.ViewCount,
  w.Tags,
  w.CreationDate,
  w.OwnerUserId,
  w.AnswerCount,
  w.CommentCount,
  w.LastActivityDate,
  w.OwnerInfo ->> 'Owner' AS OwnerDisplay,
  w.OwnerInfo ->> 'Reputation' AS OwnerReputation,
  ru.DisplayName AS ActiveFriend,
  t.TagName,
  t.Count AS TagCount,
  (w.Score * 0.5 + w.ViewCount * 0.1 + COALESCE( UpvotesForPost,0) * 1.2 - COALESCE(DownvotesForPost,0) * 0.5) AS PerformanceIndex
FROM windowed_activity w
LEFT JOIN LATERAL (
  SELECT u.DisplayName
  FROM Users u
  WHERE u.Id = w.OwnerUserId
  LIMIT 1
) AS ru ON TRUE
LEFT JOIN tag_summary t ON t.PostId = w.PostId
LEFT JOIN LATERAL (
  SELECT SUM(CASE WHEN v2.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesForPost
  FROM Votes v2
  WHERE v2.PostId = w.PostId
) AS up ON TRUE
LEFT JOIN LATERAL (
  SELECT SUM(CASE WHEN v3.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesForPost
  FROM Votes v3
  WHERE v3.PostId = w.PostId
) AS dn ON TRUE
WHERE w rn_post = 1
  AND w.LastActivityDate IS NOT NULL
ORDER BY PerformanceIndex DESC NULLS LAST
LIMIT 100;