-- {"query": "34.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 280} 
WITH ranked_users AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT Id, Reputation
    FROM ranked_users
    WHERE rank <= 100
),
user_accepted_answers AS (
    SELECT p.OwnerUserId, COUNT(a.Id) AS num_accepted_answers
    FROM Posts p
    LEFT JOIN Posts a ON p.AcceptedAnswerId = a.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
user_votes AS (
    SELECT v.UserId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS num_upvotes,
                          SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS num_downvotes
    FROM Votes v
    GROUP BY v.UserId
)
SELECT tu.Id, tu.Reputation, COALESCE(uaa.num_accepted_answers, 0) AS num_accepted_answers,
       COALESCE(uv.num_upvotes, 0) AS num_upvotes, COALESCE(uv.num_downvotes, 0) AS num_downvotes
FROM top_users tu
LEFT JOIN user_accepted_answers uaa ON tu.Id = uaa.OwnerUserId
LEFT JOIN user_votes uv ON tu.Id = uv.UserId
ORDER BY tu.Reputation DESC;