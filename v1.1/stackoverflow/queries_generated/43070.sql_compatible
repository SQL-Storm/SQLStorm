WITH HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 10000
),
TopQuestions AS (
    SELECT Id, Title, ViewCount, FavoriteCount, AnswerCount, Score, OwnerUserId
    FROM Posts
    WHERE PostTypeId = 1 AND Score > 50 AND ViewCount > 1000
),
TopAnswers AS (
    SELECT p.Id, p.ParentId, p.Score, ph.CreationDate AS LastEditDate, u.DisplayName AS LastEditor
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
    JOIN Users u ON ph.UserId = u.Id
    WHERE p.PostTypeId = 2 AND p.Score > 100
),
RecentActivity AS (
    SELECT p.Id, COUNT(ph.Id) AS EditCount, MAX(ph.CreationDate) AS LastActivity
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '3 months')
    GROUP BY p.Id
    HAVING COUNT(ph.Id) > 5
)
SELECT 
    u.DisplayName AS HighRepUser,
    q.Title AS TopQuestion,
    a.Score AS TopAnswerScore,
    ra.EditCount,
    ra.LastActivity
FROM HighReputationUsers u
JOIN TopQuestions q ON u.Id = q.OwnerUserId
JOIN TopAnswers a ON q.Id = a.ParentId
JOIN RecentActivity ra ON q.Id = ra.Id
GROUP BY
    u.DisplayName,
    q.Title,
    a.Score,
    ra.EditCount,
    ra.LastActivity,
    q.Score
ORDER BY q.Score DESC, a.Score DESC, ra.EditCount DESC
LIMIT 50;