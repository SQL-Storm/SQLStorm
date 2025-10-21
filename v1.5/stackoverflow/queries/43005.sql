-- {"query": "43005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 490} 
WITH UserScores AS (
    SELECT 
        u.Id AS UserId,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS AnswerScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY u.Id
),
TagStatistics AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY t.TagName
),
TopContributors AS (
    SELECT 
        u.DisplayName,
        (COALESCE(us.QuestionScore, 0) + COALESCE(us.AnswerScore, 0)) AS TotalScore,
        us.QuestionCount,
        us.AnswerCount
    FROM Users u
    LEFT JOIN UserScores us ON u.Id = us.UserId
    ORDER BY TotalScore DESC
    LIMIT 10
)
SELECT 
    tc.DisplayName,
    tc.TotalScore,
    tc.QuestionCount,
    tc.AnswerCount,
    ts.TagName,
    ts.PostCount,
    ts.AvgScore
FROM TopContributors tc
CROSS JOIN TagStatistics ts
ORDER BY tc.TotalScore DESC, ts.PostCount DESC;