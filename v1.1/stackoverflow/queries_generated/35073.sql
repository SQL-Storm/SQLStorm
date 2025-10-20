-- {"query": "35073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 644} 
WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, COUNT(p.Id) AS PostCount, SUM(p.Score) AS TotalScore, MAX(u.Reputation) AS Reputation
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate > now() - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 10
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        p.Score AS QuestionScore,
        COUNT(a.Id) AS AnsweredByActiveUsers,
        MAX(a.Score) AS TopAnswerScore
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN ActiveUsers au ON a.OwnerUserId = au.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > now() - INTERVAL '6 months'
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.ViewCount, p.AnswerCount, p.Score
),
TopTags AS (
    SELECT 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagUsage
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > now() - INTERVAL '6 months'
    GROUP BY TagName
    ORDER BY TagUsage DESC
    LIMIT 20
),
TagMetrics AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS Questions,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AvgScore,
        AVG(p.AnswerCount) AS AvgAnswers
    FROM Posts p
    JOIN TopTags t ON p.Tags ILIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
      AND p.CreationDate > now() - INTERVAL '6 months'
    GROUP BY t.TagName
)
SELECT
    au.DisplayName,
    au.Reputation,
    qs.Title AS RecentQuestionTitle,
    qs.CreationDate,
    qs.ViewCount,
    qs.AnswerCount,
    qs.QuestionScore,
    qs.AnsweredByActiveUsers,
    qs.TopAnswerScore,
    tm.TagName,
    tm.Questions AS RecentQuestionsWithTag,
    tm.TotalViews,
    tm.AvgScore,
    tm.AvgAnswers
FROM ActiveUsers au
JOIN QuestionStats qs ON au.Id = qs.OwnerUserId
JOIN LATERAL (
    SELECT tm.*
    FROM TagMetrics tm
    WHERE qs.Title ILIKE '%' || tm.TagName || '%'
    ORDER BY tm.Questions DESC, tm.TotalViews DESC
    LIMIT 1
) tm ON TRUE
ORDER BY au.Reputation DESC, qs.ViewCount DESC
LIMIT 100;