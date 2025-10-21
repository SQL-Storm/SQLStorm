-- {"query": "36.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 199} 
WITH ranked_users AS (
    SELECT
        Id,
        DisplayName,
        UpVotes,
        DENSE_RANK() OVER (ORDER BY UpVotes DESC) AS upvote_rank
    FROM
        Users
    WHERE
        Reputation > 100
),
answered_questions AS (
    SELECT
        p.Id AS question_id,
        p.Title AS question_title,
        COUNT(a.Id) AS answer_count
    FROM
        Posts p
    LEFT JOIN
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id, p.Title
)
SELECT
    ru.DisplayName AS top_user,
    aq.question_title,
    aq.answer_count
FROM
    ranked_users ru
JOIN
    answered_questions aq ON ru.Id = aq.question_id
WHERE
    ru.upvote_rank <= 10
ORDER BY
    aq.answer_count DESC;