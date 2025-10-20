-- {"query": "54066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1289} 

-- Benchmark query: top 100 users by reputation with aggregated metrics and top 3 posts
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
),
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)           AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)           AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    s.Id,
    s.DisplayName,
    s.Reputation,
    s.QuestionCount,
    s.AnswerCount,
    s.AvgPostScore,
    STRING_AGG(CONVERT(varchar(10), r.Id), ',') AS TopPostIds
FROM UserStats s
LEFT JOIN RankedPosts r
    ON r.OwnerUserId = s.Id
   AND r.rn <= 3
GROUP BY s.Id, s.DisplayName, s.Reputation, s.QuestionCount, s.AnswerCount, s.AvgPostScore
ORDER BY s.Reputation DESC
LIMIT 100;
