-- {"query": "20.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 792} 
WITH
-- 1) Identify top users by reputation with a mix of activity
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
-- 2) For each top user, compute a rich profile metric using correlated subqueries
UserMetrics AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.CreationDate,
    tu.LastAccessDate,
    -- Weighted activity score combining posts, comments, and badges
    (
      COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.UserId),0) * 3
      + COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = tu.UserId),0) * 2
      + COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = tu.UserId),0) * 5
      + COALESCE((SELECT SUM(ViewCount) FROM Posts p WHERE p.OwnerUserId = tu.UserId),0) / 100
    ) AS ActivityScore,
    -- Proportion of gold badges for the user
    (
      SELECT COALESCE( CAST(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS float) / NULLIF(COUNT(*),0), 0)
      FROM Badges b
      WHERE b.UserId = tu.UserId
    ) AS GoldBadgeRatio
  FROM TopUsers tu
)
-- 3) Correlated windowed analysis: rank users by ActivityScore within a rolling 100-user window
, Ranked AS (
  SELECT
    um.UserId,
    um.DisplayName,
    um.Reputation,
    um.CreationDate,
    um.LastAccessDate,
    um.ActivityScore,
    um.GoldBadgeRatio,
    ROW_NUMBER() OVER (ORDER BY um.ActivityScore DESC, um.Reputation DESC) AS ActivityRank
  FROM UserMetrics um
)
SELECT
  r.UserId,
  r.DisplayName,
  r.Reputation,
  r.CreationDate,
  r.LastAccessDate,
  r.ActivityScore,
  r.GoldBadgeRatio,
  r.ActivityRank,
  -- 4) Complex computed columns combining strings, NULLs, and date arithmetic
  CONCAT_WS(' | ',
    'User:', COALESCE(r.DisplayName, '(anonymous)'),
    'Rep:' , CAST(r.Reputation AS VARCHAR),
    'Rank:' , CAST(r.ActivityRank AS VARCHAR)
  ) AS SummaryProfile,
  -- 5) A set of related post stats via an outer join-like pattern (left joins)
  COALESCE(pq.PostCount,0) AS QuestionCount,
  COALESCE(pa.PostCount,0) AS AnswerCount,
  COALESCE(pc.PostCount,0) AS CommentCount
FROM Ranked r
LEFT JOIN (
  SELECT OwnerUserId, COUNT(*) AS PostCount
  FROM Posts
  WHERE PostTypeId = 1
  GROUP BY OwnerUserId
) pq ON pq.OwnerUserId = r.UserId
LEFT JOIN (
  SELECT OwnerUserId, COUNT(*) AS PostCount
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY OwnerUserId
) pa ON pa.OwnerUserId = r.UserId
LEFT JOIN (
  SELECT UserId, COUNT(*) AS PostCount
  FROM Comments
  GROUP BY UserId
) pc ON pc.UserId = r.UserId
ORDER BY r.ActivityScore DESC
LIMIT 50;