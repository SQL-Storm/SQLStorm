-- {"query": "69.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 164} 
WITH recursive cte AS (
    SELECT 
        p.Id AS post_id,
        p.Title AS post_title,
        COUNT(c.Id) AS comment_count
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id

    UNION ALL

    SELECT 
        p.Id,
        p.Title,
        COUNT(c.Id)
    FROM cte
    JOIN Posts p ON cte.post_id = p.ParentId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.Id, cte.post_id, p.Title
)
SELECT 
    post_id,
    post_title,
    comment_count
FROM cte
ORDER BY post_id;