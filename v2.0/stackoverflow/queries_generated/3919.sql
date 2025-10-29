-- {"query": "3919.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1836} 

WITH RecentPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),
UserBadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS AnswerCount,
        COALESCE(AVG(p.Score),0) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
TopActiveUsers AS (
    SELECT 
        ups.UserId,
        u.DisplayName,
        u.Reputation,
        ups.QuestionCount,
        ups.AnswerCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TagBasedBadges,
        ups.AvgPostScore,
        ups.LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, ups.AnswerCount DESC) AS rank
    FROM UserPostStats ups
    JOIN Users u ON u.Id = ups.UserId
    LEFT JOIN UserBadgeAgg ub ON ub.UserId = u.Id
    WHERE u.Reputation > 1000
)
SELECT
    ta.UserId,
    COALESCE(ta.DisplayName, 'Anonymous') AS DisplayName,
    ta.Reputation,
    ta.QuestionCount,
    ta.AnswerCount,
    ta.GoldBadges,
    ta.SilverBadges,
    ta.BronzeBadges,
    ta.TagBasedBadges,
    ROUND(ta.AvgPostScore,2) AS AvgPostScore,
    ta.LastPostDate,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Posts p
            WHERE p.OwnerUserId = ta.UserId
              AND p.PostTypeId = 1
              AND p.Score > 0
              AND p.Tags ILIKE '%<sql>%'
        ) THEN 'SQL Expert'
        ELSE 'Generalist'
    END AS TagProfile,
    CONCAT('https://stackoverflow.com/users/', ta.UserId) AS ProfileUrl
FROM TopActiveUsers ta
WHERE ta.rank <= 50

UNION ALL

SELECT
    NULL AS UserId,
    'Overall Statistics' AS DisplayName,
    NULL AS Reputation,
    SUM(QuestionCount) AS QuestionCount,
    SUM(AnswerCount) AS AnswerCount,
    SUM(GoldBadges) AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges,
    SUM(TagBasedBadges) AS TagBasedBadges,
    ROUND(AVG(AvgPostScore),2) AS AvgPostScore,
    MAX(LastPostDate) AS LastPostDate,
    NULL AS TagProfile,
    NULL AS ProfileUrl
FROM TopActiveUsers;
