-- {"query": "67.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 119} 
WITH ranked_users AS (
    SELECT id, reputation, displayname, row_number() OVER (ORDER BY reputation DESC) AS rank
    FROM users
),
top_users AS (
    SELECT id, displayname
    FROM ranked_users
    WHERE rank <= 10
)
SELECT p.title, p.viewcount, u.displayname as ownername, b.name as badgename
FROM posts p
JOIN top_users u ON p.owneruserid = u.id
JOIN badges b ON u.id = b.userid
WHERE p.posttypeid = 1
ORDER BY p.viewcount DESC;