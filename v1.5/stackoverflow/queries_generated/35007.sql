-- {"query": "35007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 627} 
WITH MostActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        MAX(p.CreationDate) as LastPostDate,
        SUM(p.Score) AS TotalScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 50
),
PopularTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        SUM(t.Count) AS TotalTagCount
    FROM Tags t
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
),
FastAnswerQuestions AS (
    SELECT 
        q.Id AS QuestionId,
        a.Id AS AnswerId,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/60.0 AS MinutesToAnswer
    FROM Posts q
    JOIN Posts a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
      AND a.PostTypeId = 2
      AND a.CreationDate IS NOT NULL AND q.CreationDate IS NOT NULL
      AND EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/60.0 < 30
),
HotQuestionActivity AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = q.Id
    WHERE q.PostTypeId = 1
      AND q.Score > 10
      AND q.AnswerCount >= 5
      AND q.ViewCount > 5000
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.PostCount,
    u.TotalScore,
    p.TagName,
    pq.Title AS PopularQuestionTitle,
    hq.Score AS QuestionScore,
    hq.ViewCount,
    hq.AnswerCount,
    hq.CommentCount,
    fa.MinutesToAnswer
FROM MostActiveUsers u
JOIN Posts p1 ON p1.OwnerUserId = u.UserId
JOIN PopularTags p ON POSITION('<' || p.TagName || '>' IN p1.Tags) > 0
JOIN HotQuestionActivity hq ON hq.QuestionId = p1.Id
LEFT JOIN Posts pq ON pq.Id = hq.QuestionId
LEFT JOIN FastAnswerQuestions fa ON fa.QuestionId = pq.Id
ORDER BY u.TotalScore DESC, hq.ViewCount DESC, fa.MinutesToAnswer ASC NULLS LAST
LIMIT 50;