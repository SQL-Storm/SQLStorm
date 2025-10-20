-- {"query": "43082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 481} 
WITH HighReputationUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.Reputation > 10000
),
TopQuestions AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 50 AND p.AnswerCount >= 5
),
UserQuestionStats AS (
    SELECT 
        tq.OwnerUserId,
        COUNT(*) AS QuestionCount,
        AVG(tq.Score) AS AvgScore,
        SUM(tq.ViewCount) AS TotalViews,
        MAX(tq.CreationDate) AS LastQuestionDate
    FROM TopQuestions tq
    GROUP BY tq.OwnerUserId
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    hru.DisplayName,
    hru.Reputation,
    uqs.QuestionCount,
    uqs.AvgScore,
    uqs.TotalViews,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges
FROM HighReputationUsers hru
JOIN UserQuestionStats uqs ON hru.Id = uqs.OwnerUserId
LEFT JOIN UserBadgeCounts ubc ON hru.Id = ubc.UserId
WHERE uqs.LastQuestionDate > cast('2024-10-01' as date) - INTERVAL '1 year'
ORDER BY hru.Reputation DESC, uqs.QuestionCount DESC, ubc.GoldBadges DESC
LIMIT 100;