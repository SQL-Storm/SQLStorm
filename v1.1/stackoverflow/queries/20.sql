-- {"query": "20.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 338} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, 
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_badge_users AS (
    SELECT u.Id, u.DisplayName, b.Name AS BadgeName, b.Class
    FROM ranked_users u
    JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class = 1
),
top_users_with_answers AS (
    SELECT u.Id, u.DisplayName, COUNT(p.Id) AS AnswerCount
    FROM ranked_users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
top_users_with_questions AS (
    SELECT u.Id, u.DisplayName, COUNT(p.Id) AS QuestionCount
    FROM ranked_users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
)
SELECT u.Id, u.DisplayName, u.Reputation, u.rank, 
       COALESCE(bu.BadgeName, 'No Badge') AS TopBadgeName,
       COALESCE(bu.Class, 0) AS TopBadgeClass,
       COALESCE(ua.AnswerCount, 0) AS AnswerCount,
       COALESCE(uq.QuestionCount, 0) AS QuestionCount
FROM ranked_users u
LEFT JOIN top_badge_users bu ON u.Id = bu.Id
LEFT JOIN top_users_with_answers ua ON u.Id = ua.Id
LEFT JOIN top_users_with_questions uq ON u.Id = uq.Id
ORDER BY u.rank;