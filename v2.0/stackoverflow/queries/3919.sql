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
    WHERE p.CreationDate >= CAST(CAST('2024-10-01' AS DATE) - INTERVAL '1 year' AS DATE)
),
UserBadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(AVG(p.Score), 0) AS AvgPostScore,
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
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(ub.TagBasedBadges, 0) AS TagBasedBadges,
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
    ROUND(ta.AvgPostScore, 2) AS AvgPostScore,
    ta.LastPostDate,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Posts p
            WHERE p.OwnerUserId = ta.UserId
              AND p.PostTypeId = 1
              AND p.Score > 0
              AND LOWER(p.Tags) LIKE '%<sql>%'
        ) THEN 'SQL Expert'
        ELSE 'Generalist'
    END AS TagProfile,
    'https://stackoverflow.com/users/' || CAST(ta.UserId AS VARCHAR) AS ProfileUrl,
    ta.rank
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
    ROUND(AVG(AvgPostScore), 2) AS AvgPostScore,
    MAX(LastPostDate) AS LastPostDate,
    NULL AS TagProfile,
    NULL AS ProfileUrl,
    NULL AS rank
FROM TopActiveUsers;