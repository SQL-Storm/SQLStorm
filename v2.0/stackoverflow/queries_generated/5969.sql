-- {"query": "5969.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 751} 
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate > NOW() - INTERVAL '30 days'
),
TagRelations AS (
  SELECT
    t.TagName,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate
  FROM RecentTopPosts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName
  ) AS t
  WHERE p.PostTypeId = 1
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT tp.PostId) AS PostsViewed,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount ELSE 0 END) AS BountiesEarned
  FROM Users u
  LEFT JOIN Posts tp ON tp.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = tp.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopBadgeWinners AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Date,
    b.Class
  FROM Badges b
  WHERE b.TagBased = 0
    AND b.Class IN (1,2,3)
),
Combined AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.LastActivityDate,
    'Tag' AS Source,
    tr.TagName
  FROM TagRelations tr
  LEFT JOIN RecentTopPosts rp ON rp.Id = rp.PostId
  UNION ALL
  SELECT
    u.UserId,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'User' AS Source,
    NULL AS TagName
  FROM UserActivity u
)
SELECT
  coalesce(cte.PostId, u.UserId) AS EntityId,
  cte.Source,
  cte.Title,
  cte.Tags,
  cte.Score,
  cte.ViewCount,
  cte.CreationDate,
  cte.LastActivityDate,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation,
  b.BadgeName,
  b.Date AS BadgeDate,
  b.Class AS BadgeClass
FROM
  Combined cte
  LEFT JOIN Users u ON cte.OwnerUserId = u.Id
  LEFT JOIN TopBadgeWinners b ON b.UserId = u.Id
ORDER BY
  CASE WHEN cte.Source = 'Tag' THEN 1 ELSE 2 END,
  cte.CreationDate DESC
LIMIT 100;