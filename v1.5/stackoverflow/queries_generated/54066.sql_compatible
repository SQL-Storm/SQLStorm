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
    STRING_AGG(CAST(r.Id AS VARCHAR(10)), ',') AS TopPostIds
FROM UserStats s
LEFT JOIN RankedPosts r
    ON r.OwnerUserId = s.Id
   AND r.rn <= 3
GROUP BY s.Id, s.DisplayName, s.Reputation, s.QuestionCount, s.AnswerCount, s.AvgPostScore
ORDER BY s.Reputation DESC
FETCH FIRST 100 ROWS ONLY;