WITH HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > (
        SELECT AVG(Reputation) * 1.5
        FROM Users
    )
),
QuestionsWithAcceptedAnswers AS (
    SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, COUNT(a.Id) AS AnswerCount
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId
),
TopTags AS (
    SELECT t.TagName, COUNT(p.Id) AS QuestionCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
),
UserActivity AS (
    SELECT ph.UserId, COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 24)
    GROUP BY ph.UserId
)
SELECT 
    u.DisplayName,
    u.Reputation,
    COALESCE(SUM(qa.AnswerCount), 0) AS TotalAcceptedAnswers,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    STRING_AGG(tt.TagName, ', ') AS TopContributedTags,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    AVG(COALESCE(ua.EditCount, 0)) AS AvgEdits
FROM HighReputationUsers AS u
LEFT JOIN QuestionsWithAcceptedAnswers AS qa ON u.Id = qa.OwnerUserId
LEFT JOIN UserActivity AS ua ON u.Id = ua.UserId
LEFT JOIN Badges AS b ON u.Id = b.UserId
LEFT JOIN (
    SELECT tt.TagName
    FROM TopTags AS tt
    WHERE EXISTS (
        SELECT 1
        FROM PostHistory ph
        JOIN Posts p ON ph.PostId = p.Id
        WHERE p.Tags LIKE CONCAT('%<', tt.TagName, '>%')
    )
    ORDER BY tt.QuestionCount DESC
    LIMIT 3
) AS tt ON TRUE
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT b.Id) > 5
ORDER BY TotalAcceptedAnswers DESC, ReputationRank ASC
LIMIT 10;