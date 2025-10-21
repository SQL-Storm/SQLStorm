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
SELECT tc.Id AS UserId, tc.DisplayName, tc.Reputation, ac.num_answers
FROM top_users tc
JOIN answer_count ac ON ac.question_id = tc.Id
WHERE tc.rn <= 10
ORDER BY ac.num_answers DESC, tc.Reputation DESC;