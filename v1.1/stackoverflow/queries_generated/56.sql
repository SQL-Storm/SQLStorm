-- {"query": "56.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 201} 
WITH post_answers AS (
    SELECT p.Id AS question_id, a.Id AS answer_id
    FROM Posts p
    LEFT JOIN Posts a ON p.Id = a.ParentId
    WHERE p.PostTypeId = 1
),
answer_users AS (
    SELECT pa.question_id, COUNT(DISTINCT a.OwnerUserId) AS unique_answer_users
    FROM post_answers pa
    LEFT JOIN Posts a ON pa.answer_id = a.Id
    WHERE a.OwnerUserId IS NOT NULL
    GROUP BY pa.question_id
),
accepted_answers AS (
    SELECT pa.question_id, COUNT(DISTINCT pa.answer_id) AS total_accepted_answers
    FROM post_answers pa
    LEFT JOIN Posts a ON pa.answer_id = a.Id
    WHERE a.Id = a.AcceptedAnswerId
    GROUP BY pa.question_id
)
SELECT au.question_id, au.unique_answer_users, aa.total_accepted_answers
FROM answer_users au
LEFT JOIN accepted_answers aa ON au.question_id = aa.question_id;