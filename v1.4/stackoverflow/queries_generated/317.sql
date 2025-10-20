-- {"query": "317.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20655} 
WITH
base_users AS (
  SELECT Id AS UserId, DisplayName, Reputation
  FROM Users
),
user_post_counts AS (
  SELECT OwnerUserId AS UserId, COUNT(*) AS PostCount
  FROM Posts
  GROUP BY OwnerUserId
),
top_post_candidates AS (
  SELECT p.OwnerUserId AS UserId,
         p.Id AS PostId,
         p.Title AS TopPostTitle,
         (0.5 * LN(p.Score + 1) + 0.4 * LN(p.ViewCount + 2) + 0.2 * LN((SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) + 1)) AS Hotness
  FROM Posts p
  WHERE p.PostTypeId = 1
),
top_post_per_user AS (
  SELECT UserId, PostId AS TopPostId, TopPostTitle, Hotness AS TopPostHotness
  FROM (
     SELECT *, ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY Hotness DESC) AS rn
     FROM top_post_candidates
  ) s
  WHERE rn = 1
),
top_tag_per_user AS (
  SELECT p.OwnerUserId AS UserId,
         t.TagName,
         COUNT(*) AS TagCount
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
  WHERE p.PostTypeId = 1
  GROUP BY p.OwnerUserId, t.TagName
),
top_tag_per_user_final AS (
  SELECT UserId, TagName AS TopTag
  FROM (
     SELECT *, ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS rn
     FROM top_tag_per_user
  ) s
  WHERE rn = 1
)
SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(pc.PostCount, 0) AS PostCount,
  tp.TopPostId,
  tp.TopPostTitle,
  tp.TopPostHotness,
  tt.TopTag
FROM base_users u
JOIN user_post_counts pc ON pc.UserId = u.UserId
LEFT JOIN top_post_per_user tp ON tp.UserId = u.UserId
LEFT JOIN top_tag_per_user_final tt ON tt.UserId = u.UserId
WHERE pc.PostCount > 0

UNION ALL

SELECT
  u.UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(pc.PostCount, 0) AS PostCount,
  NULL::int AS TopPostId,
  NULL::text AS TopPostTitle,
  NULL::double precision AS TopPostHotness,
  NULL::text AS TopTag
FROM base_users u
LEFT JOIN user_post_counts pc ON pc.UserId = u.UserId
WHERE COALESCE(pc.PostCount, 0) = 0;