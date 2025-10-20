-- {"query": "35010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 648} 
WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    WHERE Count > 1000
),
ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.Reputation > 2000
      AND u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
TopQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND (
            EXISTS (
                SELECT 1
                FROM PopularTags t
                WHERE p.Tags LIKE '%<' || t.TagName || '>%'
            )
          )
      AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount
    HAVING COUNT(a.Id) >= 5
),
AcceptedAnswers AS (
    SELECT q.QuestionId, a.Id AS AnswerId, a.OwnerUserId, a.Score, a.CreationDate
    FROM TopQuestions q
    JOIN Posts a ON a.Id = (SELECT AcceptedAnswerId FROM Posts WHERE Id = q.QuestionId)
    WHERE a.PostTypeId = 2
)
SELECT 
    q.QuestionId,
    q.Title AS QuestionTitle,
    u.DisplayName AS QuestionOwner,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    aa.AnswerId AS AcceptedAnswerId,
    au.DisplayName AS AcceptedAnswerOwner,
    aa.Score AS AcceptedAnswerScore,
    EXTRACT(EPOCH FROM (aa.CreationDate - q.CreationDate))/3600 AS HoursToAccepted,
    ROUND(AVG(c.Score),2) AS AvgCommentScoreOnAccepted,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesOnAccepted,
    b.Name AS AcceptedAnswerOwnerTopBadge
FROM TopQuestions q
JOIN Users u ON q.OwnerUserId = u.Id
JOIN AcceptedAnswers aa ON q.QuestionId = aa.QuestionId
LEFT JOIN Users au ON aa.OwnerUserId = au.Id
LEFT JOIN Comments c ON c.PostId = aa.AnswerId
LEFT JOIN Votes v ON v.PostId = aa.AnswerId
LEFT JOIN Badges b ON b.UserId = aa.OwnerUserId AND b.Class = 1
WHERE q.Score > 5
  AND (q.OwnerUserId IN (SELECT Id FROM ActiveUsers) OR aa.OwnerUserId IN (SELECT Id FROM ActiveUsers))
GROUP BY 
    q.QuestionId, q.Title, u.DisplayName, q.Score, q.ViewCount, q.AnswerCount,
    aa.AnswerId, au.DisplayName, aa.Score, q.CreationDate, aa.CreationDate, b.Name
ORDER BY q.ViewCount DESC
LIMIT 50;