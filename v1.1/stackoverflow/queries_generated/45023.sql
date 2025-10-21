-- {"query": "45023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 419}
WITH TopContributors AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(p.Score + COALESCE(a.Score, 0)) AS TotalScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
TagPerformance AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AverageTagScore,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    GROUP BY t.TagName
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.QuestionCount,
    tc.AnswerCount,
    tc.TotalScore,
    tp.TagName AS MostFrequentTag,
    tp.PostCount AS TagPostCount,
    tp.AverageTagScore
FROM TopContributors tc
JOIN TagPerformance tp ON tp.PostCount = (
    SELECT MAX(PostCount) 
    FROM TagPerformance
)
ORDER BY tc.TotalScore DESC
LIMIT 100;
