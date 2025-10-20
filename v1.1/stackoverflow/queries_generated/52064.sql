-- {"query": "52064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 452} 

WITH TagPostCounts AS (
  SELECT p.OwnerUserId AS UserId,
         TRIM(unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagName,
         COUNT(*) AS PostCount
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  GROUP BY p.OwnerUserId, TagName
),
UserTopTag AS (
  SELECT UserId, TagName AS TopTag,
         ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY PostCount DESC) AS rn
  FROM TagPostCounts
),
BadgeCounts AS (
  SELECT UserId, Class, COUNT(*) AS BadgeCount
  FROM Badges
  GROUP BY UserId, Class
),
UserStats AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         COALESCE(bc_gold.BadgeCount, 0) AS GoldBadges,
         COALESCE(bc_silver.BadgeCount, 0) AS SilverBadges,
         COALESCE(bc_bronze.BadgeCount, 0) AS BronzeBadges,
         (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
         (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
         (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
         utt.TopTag
  FROM Users u
  LEFT JOIN BadgeCounts bc_gold ON u.Id = bc_gold.UserId AND bc_gold.Class = 1
  LEFT JOIN BadgeCounts bc_silver ON u.Id = bc_silver.UserId AND bc_silver.Class = 2
  LEFT JOIN BadgeCounts bc_bronze ON u.Id = bc_bronze.UserId AND bc_bronze.Class = 3
  LEFT JOIN UserTopTag utt ON u.Id = utt.UserId AND utt.rn = 1
)
SELECT * FROM UserStats
ORDER BY GoldBadges DESC, Reputation DESC
LIMIT 20;
