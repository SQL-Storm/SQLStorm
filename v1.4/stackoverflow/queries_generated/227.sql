-- {"query": "227.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8951} 
WITH
user_stats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COUNT(p.Id) AS PostCount,
         COALESCE(SUM(p.Score), 0) AS TotalScore,
         MAX(p.CreationDate) AS LastPostDate,
         (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
user_tags AS (
  SELECT p.OwnerUserId AS UserId,
         t.TagName
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
per_user_posts AS (
  SELECT p.OwnerUserId AS UserId,
         p.Title,
         p.Score,
         p.CreationDate,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  us.UserId,
  us.DisplayName,
  us.PostCount,
  us.TotalScore,
  us.LastPostDate,
  us.GoldBadges,
  (SELECT string_agg(DISTINCT ut.TagName, ', ' ORDER BY TagName)
   FROM user_tags ut WHERE ut.UserId = us.UserId) AS TopTags,
  (SELECT string_agg(p.Title, ' | ' ORDER BY p.Score DESC NULLS LAST, p.CreationDate DESC)
   FROM per_user_posts pu
   WHERE pu.UserId = us.UserId AND pu.rn <= 3) AS TopRecentPostTitles
FROM user_stats us
UNION ALL
SELECT u.Id AS UserId,
       u.DisplayName,
       0 AS PostCount,
       0 AS TotalScore,
       NULL AS LastPostDate,
       0 AS GoldBadges,
       '' AS TopTags,
       NULL AS TopRecentPostTitles
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
ORDER BY 4 DESC NULLS LAST
LIMIT 50;