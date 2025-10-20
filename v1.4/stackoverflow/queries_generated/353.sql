-- {"query": "353.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 18213} 
WITH
  -- Basic per-user stats and a correlated subquery (PositivePostCount)
  UserBase AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS CreationDate,
      u.LastAccessDate,
      COALESCE(pStats.TotalPosts, 0) AS TotalPosts,
      COALESCE(pStats.TotalPostScore, 0) AS TotalPostScore,
      COALESCE((SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Score > 0), 0) AS PositivePostCount
    FROM Users u
    LEFT JOIN (
      SELECT OwnerUserId, COUNT(*) AS TotalPosts, SUM(Score) AS TotalPostScore
      FROM Posts
      GROUP BY OwnerUserId
    ) pStats ON pStats.OwnerUserId = u.Id
  ),
  -- Comments per user
  UserComments AS (
    SELECT UserId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY UserId
  ),
  -- Gold badge counts per user
  GoldBadgeUsers AS (
    SELECT b.UserId, COUNT(*) AS GoldBadgeCount
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
  ),
  -- Top 3 posts per user as JSON
  TopPosts AS (
    SELECT p.OwnerUserId AS UserId,
           p.Id AS PostId,
           p.Title,
           p.Score,
           p.LastActivityDate,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.LastActivityDate DESC NULLS LAST) AS rn
    FROM Posts p
  ),
  TopPostsJSON AS (
    SELECT UserId, json_agg(json_build_object('PostId', PostId, 'Title', Title, 'Score', Score)) AS TopPosts
    FROM TopPosts
    WHERE rn <= 3
    GROUP BY UserId
  ),
  -- Last activity date per user
  MostRecentPostDate AS (
    SELECT OwnerUserId, MAX(LastActivityDate) AS LastPostDate
    FROM Posts
    GROUP BY OwnerUserId
  ),
  -- Top tag per user by usage
  TopTagName AS (
    SELECT UserId, TagName
    FROM (
      SELECT UserId, TagName, TagCount,
             ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC, TagName) AS rn
      FROM (
        SELECT p.OwnerUserId AS UserId,
               t.TagName,
               COUNT(*) AS TagCount
        FROM Posts p
        CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
        WHERE p.OwnerUserId IS NOT NULL AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, t.TagName
      ) AS perUser
    ) AS ranked
    WHERE rn = 1
  ),
  -- Main enriched dataset
  MainData AS (
    SELECT
      ub.UserId,
      ub.DisplayName,
      ub.Reputation,
      ub.CreationDate,
      ub.LastAccessDate,
      COALESCE(ub.TotalPosts, 0) AS TotalPosts,
      COALESCE(ub.TotalPostScore, 0) AS TotalPostScore,
      COALESCE(c.CommentCount, 0) AS CommentCount,
      COALESCE(bg.GoldBadgeCount, 0) AS GoldBadges,
      COALESCE(tobj.TopPosts, '[]'::json) AS TopPosts,
      rt.LastPostDate,
      tt.TagName AS TopTagName,
      (COALESCE(ub.TotalPostScore, 0) * 1.5
       + COALESCE(c.CommentCount, 0) * 0.5
       + COALESCE(bg.GoldBadgeCount, 0) * 25.0
       + CASE WHEN rt.LastPostDate > now() - interval '365 days' THEN 50 ELSE 0 END) AS EngScore
    FROM UserBase ub
    LEFT JOIN UserComments c ON c.UserId = ub.UserId
    LEFT JOIN GoldBadgeUsers bg ON bg.UserId = ub.UserId
    LEFT JOIN TopPostsJSON tobj ON tobj.UserId = ub.UserId
    LEFT JOIN MostRecentPostDate rt ON rt.OwnerUserId = ub.UserId
    LEFT JOIN TopTagName tt ON tt.UserId = ub.UserId
  ),
  -- Alternative dataset to exercise UNION ALL
  AltData AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS CreationDate,
      u.LastAccessDate,
      0 AS TotalPosts,
      0 AS TotalPostScore,
      0 AS CommentCount,
      0 AS GoldBadges,
      '[]'::json AS TopPosts,
      NULL AS LastPostDate,
      NULL AS TopTagName,
      0.0 AS EngScore
    FROM Users u
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  )
SELECT *
FROM MainData
UNION ALL
SELECT *
FROM AltData
ORDER BY EngScore DESC
LIMIT 100;