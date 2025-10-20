-- {"query": "35076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 585} 
WITH top_answerers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2 AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 20
),
fastest_accepted_answers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        a.Id AS AnswerId,
        a.OwnerUserId AS ResponderId,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/60 AS AnswerTimeMinutes
    FROM Posts q
    JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
        AND q.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
),
badge_leaders AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze
    FROM Badges b
    WHERE b.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY b.UserId
    HAVING SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) > 2
)
SELECT 
    ta.DisplayName AS UserName,
    ta.AnswerCount,
    ta.TotalScore,
    ROUND(ta.AvgScore, 2) AS AvgScore,
    COALESCE(bl.Gold, 0) AS GoldBadges,
    COALESCE(bl.Silver, 0) AS SilverBadges,
    COALESCE(bl.Bronze, 0) AS BronzeBadges,
    ROUND(AVG(faa.AnswerTimeMinutes), 2) AS AvgTimeToAcceptedAnswerMinutes,
    COUNT(faa.AnswerId) AS AcceptedAnswers
FROM top_answerers ta
LEFT JOIN badge_leaders bl ON bl.UserId = ta.UserId
LEFT JOIN fastest_accepted_answers faa ON faa.ResponderId = ta.UserId
GROUP BY 
    ta.UserId, ta.DisplayName, ta.AnswerCount, ta.TotalScore, ta.AvgScore,
    bl.Gold, bl.Silver, bl.Bronze
HAVING COUNT(faa.AnswerId) > 5
ORDER BY AvgScore DESC, GoldBadges DESC
LIMIT 20;