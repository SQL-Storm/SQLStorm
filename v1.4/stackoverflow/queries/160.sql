-- {"query": "160.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2297} 
WITH
RecentPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    string_to_array(substr(p.Tags, 2, char_length(p.Tags) - 2), '><') AS TagArray
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(r.PostId) AS PostCount,
    COALESCE(SUM(r.Score), 0) AS ScoreSum,
    COALESCE(AVG(r.Score), 0) AS AvgScore
  FROM Users u
  LEFT JOIN RecentPosts r ON r.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
  SELECT
    UserId,
    DisplayName,
    PostCount,
    ScoreSum,
    AvgScore,
    ROW_NUMBER() OVER (
      ORDER BY
        ScoreSum DESC NULLS LAST,
        AvgScore DESC NULLS LAST
    ) AS rn
  FROM UserStats
)
SELECT
  tu.UserId,
  tu.DisplayName,
  tu.PostCount,
  tu.ScoreSum,
  tu.AvgScore,
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = tu.UserId) AS CommentCount,
  (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.ViewCount > 0) AS NonZeroViewPosts
FROM TopUsers tu
WHERE tu.rn <= 10
ORDER BY tu.ScoreSum DESC NULLS LAST, tu.AvgScore DESC NULLS LAST;