-- {"query": "25060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2255} 
WITH UserStats AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           u.Reputation,
           COALESCE(p.QuestionCount, 0) AS QuestionCount,
           COALESCE(p.AnswerCount, 0)   AS AnswerCount,
           COALESCE(b.GoldBadgeCount, 0)   AS GoldBadgeCount,
           COALESCE(b.SilverBadgeCount, 0) AS SilverBadgeCount,
           COALESCE(b.BronzeBadgeCount, 0) AS BronzeBadgeCount,
           (SELECT MAX(CreationDate) FROM Posts      WHERE OwnerUserId = u.Id) AS LastPostDate,
           (SELECT MAX(CreationDate) FROM Comments   WHERE UserId      = u.Id) AS LastCommentDate
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
        FROM Posts
        GROUP BY OwnerUserId
    ) p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId,
               SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
               SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
               SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
),

TagUsage AS (
    SELECT p.OwnerUserId,
           UNNEST(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag,
           COUNT(*) AS TagPostCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),

TopTags AS (
    SELECT OwnerUserId,
           STRING_AGG(Tag || ':' || TagPostCount, ', ' ORDER BY TagPostCount DESC) AS Top5Tags
    FROM TagUsage
    GROUP BY OwnerUserId
),

RecentActivity AS (
    SELECT us.UserId,
           us.DisplayName,
           us.Reputation,
           us.QuestionCount,
           us.AnswerCount,
           us.GoldBadgeCount,
           us.SilverBadgeCount,
           us.BronzeBadgeCount,
           GREATEST(us.LastPostDate, us.LastCommentDate) AS LastActivityDate,
           ROW_NUMBER() OVER (PARTITION BY us.UserId
                              ORDER BY GREATEST(us.LastPostDate, us.LastCommentDate) DESC) AS ActivityRank,
           tt.Top5Tags
    FROM UserStats us
    LEFT JOIN TopTags tt ON tt.OwnerUserId = us.UserId
)

SELECT ra.UserId,
       ra.DisplayName,
       ra.Reputation,
       ra.QuestionCount,
       ra.AnswerCount,
       ra.GoldBadgeCount,
       ra.SilverBadgeCount,
       ra.BronzeBadgeCount,
       ra.LastActivityDate,
       ra.ActivityRank,
       COALESCE(ra.Top5Tags, 'No tags') AS TopTags
FROM RecentActivity ra
WHERE ra.ActivityRank = 1
  AND (ra.Reputation > 10000 OR ra.GoldBadgeCount >= 5)

UNION ALL

SELECT NULL AS UserId,
       'Aggregate' AS DisplayName,
       SUM(ra.Reputation)                AS Reputation,
       SUM(ra.QuestionCount)             AS QuestionCount,
       SUM(ra.AnswerCount)               AS AnswerCount,
       SUM(ra.GoldBadgeCount)            AS GoldBadgeCount,
       SUM(ra.SilverBadgeCount)          AS SilverBadgeCount,
       SUM(ra.BronzeBadgeCount)          AS BronzeBadgeCount,
       MAX(ra.LastActivityDate)          AS LastActivityDate,
       NULL                              AS ActivityRank,
       NULL                              AS TopTags
FROM RecentActivity ra
WHERE ra.Reputation IS NOT NULL
ORDER BY Reputation DESC
LIMIT 100;