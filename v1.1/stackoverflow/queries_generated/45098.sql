-- {"query": "45098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 381}
WITH TopQuestionAuthors AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10
),
TagPerformance AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        SUM(p.ViewCount) AS TotalViews
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
)
SELECT 
    tqa.UserId,
    tqa.DisplayName,
    tqa.QuestionCount,
    tqa.AvgQuestionScore,
    tp.TagName AS MostPopularTag,
    tp.PostCount AS TagPostCount,
    tp.AvgTagScore,
    tqa.MaxViewCount
FROM TopQuestionAuthors tqa
JOIN TagPerformance tp ON tp.PostCount > 50
ORDER BY tqa.QuestionCount * tp.AvgTagScore DESC
LIMIT 100;
