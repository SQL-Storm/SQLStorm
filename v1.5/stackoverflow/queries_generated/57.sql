-- {"query": "57.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 265} 
WITH cte_users_rep AS (
    SELECT 
        Id AS user_id,
        Reputation,
        CreationDate
    FROM Users
    WHERE Reputation > 1000
),
cte_high_reputation_users AS (
    SELECT 
        user_id,
        MAX(Reputation) AS max_reputation
    FROM cte_users_rep
    GROUP BY user_id
),
cte_top_users AS (
    SELECT 
        HR.user_id,
        HR.max_reputation,
        U.CreationDate
    FROM cte_high_reputation_users HR
    JOIN Users U ON HR.user_id = U.Id
),
cte_user_activity AS (
    SELECT 
        U.Id AS user_id,
        COUNT(DISTINCT P.Id) AS num_posts,
        COUNT(DISTINCT V.Id) AS num_votes
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id
)
SELECT 
    TU.user_id,
    TU.max_reputation,
    UA.num_posts,
    UA.num_votes
FROM cte_top_users TU
JOIN cte_user_activity UA ON TU.user_id = UA.user_id
ORDER BY TU.max_reputation DESC, UA.num_posts DESC, UA.num_votes DESC;