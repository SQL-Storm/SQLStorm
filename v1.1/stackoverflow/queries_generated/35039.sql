-- {"query": "35039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 581} 
WITH UserAnswerStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore,
        COUNT(DISTINCT a.ParentId) AS DistinctQuestionsAnswered
    FROM Users u
    JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT
        LOWER(TRIM(REPLACE(REPLACE(tag.value, '<', ''), '>', ''))) AS TagName,
        COUNT(*) AS UsageCount
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags, 2, length(p.Tags)-2), '><')) AS tag(value)
    WHERE p.PostTypeId = 1
    GROUP BY LOWER(TRIM(REPLACE(REPLACE(tag.value, '<', ''), '>', '')))
),
TopTags AS (
    SELECT TagName
    FROM TagPopularity
    ORDER BY UsageCount DESC
    LIMIT 10
),
UserTopTags AS (
    SELECT 
        u.Id AS UserId,
        t.TagName,
        COUNT(*) AS TagAnswers
    FROM Posts a
    JOIN Users u ON u.Id = a.OwnerUserId
    JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(q.Tags, 2, length(q.Tags)-2), '><')) AS tag(value)
    JOIN TopTags t ON LOWER(TRIM(REPLACE(REPLACE(tag.value, '<', ''), '>', ''))) = t.TagName
    WHERE a.PostTypeId = 2
    GROUP BY u.Id, t.TagName
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.TotalAnswers,
    uas.TotalAnswerScore,
    uas.AvgAnswerScore,
    uas.MaxAnswerScore,
    uas.MinAnswerScore,
    uas.DistinctQuestionsAnswered,
    t.TagName AS TopTag,
    ut.TagAnswers AS AnswersInTag
FROM
    UserAnswerStats uas
JOIN (
    SELECT
        ut.UserId,
        ut.TagName,
        ut.TagAnswers,
        ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY ut.TagAnswers DESC) AS rn
    FROM UserTopTags ut
) ut ON ut.UserId = uas.UserId AND ut.rn = 1
JOIN TopTags t ON ut.TagName = t.TagName
WHERE uas.TotalAnswers > 20
ORDER BY uas.TotalAnswerScore DESC
LIMIT 50;