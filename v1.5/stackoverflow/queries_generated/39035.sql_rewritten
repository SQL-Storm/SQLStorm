-- {"query": "39035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2144} 
WITH
RecentQuestions AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        REGEXP_REPLACE(p.Tags, '[<>]', ',', 'g') AS TagString
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate BETWEEN cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' AND cast('2024-10-01 12:34:56' as timestamp)
),
UserTagStats AS (
    SELECT
        rq.OwnerUserId AS UserId,
        tag AS Tag,
        COUNT(*) AS QCount,
        AVG(rq.Score) AS AvgScore
    FROM RecentQuestions rq
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(TRIM(BOTH ',' FROM rq.TagString), ',')) AS tag
    ) x
    GROUP BY rq.OwnerUserId, tag
    HAVING COUNT(*) > 5
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank
    FROM Users u
    WHERE u.Reputation >= (SELECT MAX(Reputation) * 0.8 FROM Users)
),
TopUserTags AS (
    SELECT
        uts.UserId,
        uts.Tag,
        uts.QCount,
        uts.AvgScore,
        ROW_NUMBER() OVER (PARTITION BY uts.UserId ORDER BY uts.QCount DESC, uts.AvgScore DESC) AS TagRank
    FROM UserTagStats uts
    WHERE uts.UserId IN (SELECT Id FROM TopUsers)
),
TopUserBadges AS (
    SELECT
        b.UserId,
        b.Name        AS BadgeName,
        COUNT(*)      AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC) AS BadgeRank
    FROM Badges b
    WHERE b.UserId IN (SELECT Id FROM TopUsers)
    GROUP BY b.UserId, b.Name
)
SELECT
    tu.UserRank,
    tu.Id        AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tut.Tag      AS TopTag,
    tut.QCount   AS TagQuestionCount,
    tut.AvgScore AS TagAvgScore,
    tub.BadgeName,
    tub.BadgeCount
FROM TopUsers tu
LEFT JOIN TopUserTags tut
  ON tut.UserId = tu.Id
 AND tut.TagRank = 1
LEFT JOIN TopUserBadges tub
  ON tub.UserId = tu.Id
 AND tub.BadgeRank = 1
ORDER BY tu.UserRank;