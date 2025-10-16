-- {"query": "13025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 662} 

WITH HighReputationUsers AS (
    SELECT Id, Reputation, DisplayName
    FROM Users
    WHERE Reputation > (SELECT AVG(Reputation) * 1.5 FROM Users)
),
TopQuestions AS (
    SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, COUNT(ph.Id) AS EditCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount
    HAVING COUNT(ph.Id) > 0
),
AnswerMetrics AS (
    SELECT p.ParentId AS QuestionId, 
           COUNT(p.Id) AS AnswerCount, 
           AVG(p.Score) AS AvgAnswerScore,
           MAX(p.Score) AS MaxAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
UserActivity AS (
    SELECT u.Id AS UserId, 
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.PostId END) AS PostEdits,
           COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.PostId END) AS QuestionsCreated
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id
)
SELECT 
    hru.DisplayName,
    tq.Title,
    tq.CreationDate,
    tq.Score,
    tq.ViewCount,
    tq.EditCount,
    COALESCE(am.AnswerCount, 0) AS AnswerCount,
    COALESCE(am.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(am.MaxAnswerScore, 0) AS MaxAnswerScore,
    ua.PostEdits,
    ua.QuestionsCreated,
    RANK() OVER (PARTITION BY tq.Id ORDER BY tq.Score DESC, ua.PostEdits DESC) AS PerformanceRank
FROM HighReputationUsers hru
JOIN UserActivity ua ON hru.Id = ua.UserId
JOIN TopQuestions tq ON hru.Id = tq.OwnerUserId
LEFT JOIN AnswerMetrics am ON tq.Id = am.QuestionId
WHERE tq.CreationDate > CURRENT_DATE - INTERVAL '6 MONTHS'
  AND (ua.PostEdits + ua.QuestionsCreated) > (SELECT AVG(PostEdits + QuestionsCreated) FROM UserActivity)
ORDER BY PerformanceRank, tq.CreationDate DESC
LIMIT 100;
