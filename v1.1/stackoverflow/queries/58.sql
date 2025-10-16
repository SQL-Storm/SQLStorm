WITH answer_count AS (
    SELECT p.Id AS question_id, COUNT(a.Id) AS num_answers
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
),
top_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
)
SELECT tu.Id AS UserId, tu.DisplayName, tu.Reputation, ac.num_answers
FROM top_users tu
JOIN answer_count ac ON ac.question_id = tu.Id
WHERE tu.rn <= 10
GROUP BY tu.Id, tu.DisplayName, tu.Reputation, ac.num_answers, tu.rn
ORDER BY ac.num_answers DESC, tu.Reputation DESC;