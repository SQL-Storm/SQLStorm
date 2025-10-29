-- {"query": "5945.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 605}
WITH TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS rn
  FROM Users u
),
RecentActivity AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) AS PostsCreatedLast30d
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
  GROUP BY p.OwnerUserId
),
BadgeActivity AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesEarned
  FROM Badges b
  WHERE b.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY
  GROUP BY b.UserId
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(t.Count) AS TagTotalUses
  FROM Tags t
  GROUP BY t.TagName
  ORDER BY TagTotalUses DESC
  FETCH FIRST 50 ROWS ONLY
),
Combined AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    ra.PostsCreatedLast30d,
    ba.BadgesEarned,
    tt.TagName AS TopTag,
    tt.TagTotalUses
  FROM TopUsers tu
  LEFT JOIN RecentActivity ra ON ra.UserId = tu.UserId
  LEFT JOIN BadgeActivity ba ON ba.UserId = tu.UserId
  CROSS JOIN TopTags tt
  WHERE COALESCE(ba.BadgesEarned, 0) >= 0
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.PostsCreatedLast30d,
  c.BadgesEarned,
  c.TopTag,
  c.TagTotalUses,
  RANK() OVER (PARTITION BY c.TopTag ORDER BY c.Reputation DESC, c.PostsCreatedLast30d DESC) AS RankWithinTag,
  (COALESCE(c.Reputation, 0) * 2
   + COALESCE(c.PostsCreatedLast30d, 0) * 5
   + COALESCE(c.BadgesEarned, 0) * 3
   + COALESCE(c.TagTotalUses, 0) * 1) AS BenchmarkScore
FROM Combined c
GROUP BY
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.PostsCreatedLast30d,
  c.BadgesEarned,
  c.TopTag,
  c.TagTotalUses
ORDER BY BenchmarkScore DESC
FETCH FIRST 100 ROWS ONLY;