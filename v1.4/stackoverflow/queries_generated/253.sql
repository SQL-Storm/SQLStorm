-- {"query": "253.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 10022} 
WITH
LatestPost AS (
  SELECT DISTINCT ON (p.OwnerUserId) p.OwnerUserId AS UserId,
         p.Id AS LatestPostId,
         COALESCE(p.LastActivityDate, p.CreationDate) AS LastActivityDate
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  ORDER BY p.OwnerUserId, COALESCE(p.LastActivityDate, p.CreationDate) DESC
),
UserPosts AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    p.Id AS PostId,
    p.LastActivityDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViews
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
UserStats AS (
  SELECT
    up.UserId,
    up.DisplayName,
    max(up.LastActivityDate) AS LastActivityDate,
    count(up.PostId) AS NumPosts,
    coalesce(sum(up.PostScore), 0) AS TotalPostScore,
    coalesce(avg(up.PostScore), 0) AS AvgPostScore,
    coalesce(sum(up.PostViews), 0) AS TotalViews
  FROM UserPosts up
  GROUP BY up.UserId, up.DisplayName
),
RankedUsers AS (
  SELECT
    s.UserId,
    s.DisplayName,
    s.LastActivityDate,
    s.NumPosts,
    s.TotalPostScore,
    s.AvgPostScore,
    s.TotalViews,
    ROW_NUMBER() OVER (ORDER BY s.LastActivityDate DESC NULLS LAST) AS RecencyRank
  FROM UserStats s
),
TopTag AS (
  SELECT u.Id AS UserId,
         (
           SELECT t.tagname
           FROM Posts p2
           CROSS JOIN LATERAL unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags) - 2), '><')) AS t(tagname)
           WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1
           GROUP BY t.tagname
           ORDER BY count(*) DESC
           LIMIT 1
         ) AS TopTag
  FROM Users u
),
BadgeCounts AS (
  SELECT UserId, count(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId
),
CommentCounts AS (
  SELECT OwnerUserId AS UserId, count(*) AS CommentCount
  FROM Comments
  GROUP BY OwnerUserId
)
(
  SELECT
    ru.UserId,
    ru.DisplayName,
    ru.NumPosts,
    ru.TotalViews,
    ru.TotalPostScore,
    ru.AvgPostScore,
    ru.LastActivityDate,
    lp.LatestPostId,
    COALESCE(bc.BadgeCount, 0) AS BadgeCount,
    COALESCE(cc.CommentCount, 0) AS CommentCount,
    tt.TopTag,
    ru.RecencyRank
  FROM RankedUsers ru
  LEFT JOIN LatestPost lp ON lp.UserId = ru.UserId
  LEFT JOIN TopTag tt ON tt.UserId = ru.UserId
  LEFT JOIN BadgeCounts bc ON bc.UserId = ru.UserId
  LEFT JOIN CommentCounts cc ON cc.UserId = ru.UserId
  ORDER BY ru.RecencyRank
  LIMIT 100
)
UNION ALL
(
  SELECT
    -1 AS UserId,
    'Summary: All Users'::text AS DisplayName,
    0 AS NumPosts,
    0::bigint AS TotalViews,
    0::numeric AS TotalPostScore,
    0::numeric AS AvgPostScore,
    NULL::timestamp AS LastActivityDate,
    NULL::int AS LatestPostId,
    0 AS BadgeCount,
    0 AS CommentCount,
    NULL::text AS TopTag,
    0 AS RecencyRank
)