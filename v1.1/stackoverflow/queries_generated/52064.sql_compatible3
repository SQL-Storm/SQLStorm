WITH TagPostCounts AS (
  SELECT p.OwnerUserId AS UserId,
         TRIM(tag) AS TagName,
         COUNT(*) AS PostCount
  FROM Posts p,
       LATERAL (
         SELECT value AS tag
         FROM UNNEST(
           -- split tags string like '<tag1><tag2>' into array of tags
           regexp_split_to_array(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><')
         ) AS t(value)
       ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
  GROUP BY p.OwnerUserId, TRIM(tag)
),
UserTopTag AS (
  SELECT UserId, TagName AS TopTag,
         ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY PostCount DESC) AS rn
  FROM TagPostCounts
  GROUP BY UserId, TagName, PostCount
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
  GROUP BY u.Id, u.DisplayName, u.Reputation, bc_gold.BadgeCount, bc_silver.BadgeCount, bc_bronze.BadgeCount, utt.TopTag
)
SELECT Id, DisplayName, Reputation, GoldBadges, SilverBadges, BronzeBadges,
       QuestionCount, AnswerCount, AvgPostScore, TopTag
FROM UserStats
ORDER BY GoldBadges DESC, Reputation DESC
LIMIT 20;