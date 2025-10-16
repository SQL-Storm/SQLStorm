-- {"query": "64.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 211} 
WITH ranked_users AS (
    SELECT 
        Id, 
        Reputation, 
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
),
top_users AS (
    SELECT Id
    FROM ranked_users
    WHERE rank <= 100
)
SELECT 
    p.Id AS post_id,
    p.Title,
    u.DisplayName AS owner_name,
    ph.PostHistoryTypeId,
    ph.CreationDate AS history_date,
    pt.Name AS post_type,
    ph.Comment,
    v.VoteTypeId,
    COUNT(v.Id) AS vote_count
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
JOIN PostHistory ph ON p.Id = ph.PostId
JOIN PostTypes pt ON p.PostTypeId = pt.Id
JOIN Votes v ON p.Id = v.PostId
INNER JOIN top_users tu ON u.Id = tu.Id
GROUP BY p.Id, p.Title, u.DisplayName, ph.PostHistoryTypeId, ph.CreationDate, pt.Name, ph.Comment, v.VoteTypeId;