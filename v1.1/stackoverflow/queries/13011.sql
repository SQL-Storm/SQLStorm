-- {"query": "13011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 836} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastActivityDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year'
    GROUP BY u.Id
),
HighReputationUsers AS (
    SELECT 
        UserId,
        QuestionsAsked,
        AnswersProvided,
        TotalQuestionScore,
        TotalAnswerScore,
        AvgPostScore,
        LastActivityDate,
        RANK() OVER (ORDER BY AvgPostScore DESC, TotalQuestionScore + TotalAnswerScore DESC) AS UserRank
    FROM UserActivity
    WHERE TotalQuestionScore + TotalAnswerScore > 1000
),
TopUserBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    JOIN HighReputationUsers hru ON b.UserId = hru.UserId
    WHERE hru.UserRank <= 10
    GROUP BY b.UserId
),
TopUserPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    JOIN HighReputationUsers hru ON p.OwnerUserId = hru.UserId
    WHERE hru.UserRank <= 10 AND p.PostTypeId IN (1, 2)
)
SELECT 
    hru.UserId,
    u.DisplayName,
    hru.QuestionsAsked,
    hru.AnswersProvided,
    hru.TotalQuestionScore,
    hru.TotalAnswerScore,
    hru.AvgPostScore,
    hru.LastActivityDate,
    COALESCE(tub.TotalBadges, 0) AS TotalBadges,
    COALESCE(tub.GoldBadges, 0) AS GoldBadges,
    COALESCE(tub.SilverBadges, 0) AS SilverBadges,
    COALESCE(tub.BronzeBadges, 0) AS BronzeBadges,
    tup.Title AS TopPostTitle,
    tup.Score AS TopPostScore
FROM HighReputationUsers hru
JOIN Users u ON hru.UserId = u.Id
LEFT JOIN TopUserBadges tub ON hru.UserId = tub.UserId
LEFT JOIN TopUserPosts tup ON hru.UserId = tup.OwnerUserId AND tup.PostRank = 1
WHERE hru.UserRank <= 10
ORDER BY hru.UserRank, TotalBadges DESC;