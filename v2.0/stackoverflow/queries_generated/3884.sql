-- {"query": "3884.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2222} 

WITH 
-- Count badges per user, keeping users with no badges
UserBadgeCounts AS (
    SELECT 
        u.Id            AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END),0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END),0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END),0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- Gather post statistics per user
UserPostStats AS (
    SELECT 
        u.Id                                            AS UserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)     AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)     AS AnswerCount,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 1),0) AS AvgQuestionScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2),0) AS AvgAnswerScore,
        MAX(p.LastActivityDate)                         AS LastActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),

-- Determine each user's most used tag (requires parsing the Tags column)
UserTagActivity AS (
    SELECT 
        ub.UserId,
        t.TagName,
        COUNT(*)                                              AS TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY ub.UserId 
                           ORDER BY COUNT(*) DESC)           AS TagRank
    FROM UserBadgeCounts ub
    JOIN Posts p ON p.OwnerUserId = ub.UserId
    -- split the '<tag1><tag2>' format into rows
    JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS Tag
    ) AS pt ON true
    JOIN Tags t ON t.TagName = pt.Tag
    GROUP BY ub.UserId, t.TagName
),

-- Assemble the “top” users (reputation > 1k) with a rank
TopUsers AS (
    SELECT 
        ub.UserId,
        ub.DisplayName,
        ub.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.AvgQuestionScore,
        ups.AvgAnswerScore,
        ups.LastActivity,
        COALESCE((
            SELECT TagName 
            FROM UserTagActivity uta 
            WHERE uta.UserId = ub.UserId AND uta.TagRank = 1
        ), 'NoTag')                                            AS TopTag,
        ROW_NUMBER() OVER (ORDER BY ub.Reputation DESC)       AS ReputationRank
    FROM UserBadgeCounts ub
    JOIN UserPostStats ups ON ups.UserId = ub.UserId
    WHERE ub.Reputation > 1000
)

-- Final result set: top 100 users + recent newcomers (union all)
SELECT
    tu.ReputationRank,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.QuestionCount,
    tu.AnswerCount,
    ROUND(tu.AvgQuestionScore, 2) AS AvgQScore,
    ROUND(tu.AvgAnswerScore, 2)   AS AvgAScore,
    COALESCE(TO_CHAR(tu.LastActivity, 'YYYY-MM-DD'), 'Never') AS LastActivityDate,
    tu.TopTag,
    CASE 
        WHEN tu.GoldBadges >= 5   THEN 'Elite'
        WHEN tu.SilverBadges >=10 THEN 'Pro'
        ELSE 'Member'
    END AS UserTier
FROM TopUsers tu
WHERE tu.ReputationRank <= 100

UNION ALL

SELECT
    NULL                               AS ReputationRank,
    u.DisplayName,
    u.Reputation,
    0          AS GoldBadges,
    0          AS SilverBadges,
    0          AS BronzeBadges,
    0          AS QuestionCount,
    0          AS AnswerCount,
    0.0        AS AvgQScore,
    0.0        AS AvgAScore,
    'Never'    AS LastActivityDate,
    'NoTag'    AS TopTag,
    'Newbie'   AS UserTier
FROM Users u
WHERE u.Id NOT IN (SELECT UserId FROM TopUsers)
  AND u.CreationDate > CURRENT_DATE - INTERVAL '30 day'

ORDER BY ReputationRank NULLS LAST, Reputation DESC
LIMIT 150;
