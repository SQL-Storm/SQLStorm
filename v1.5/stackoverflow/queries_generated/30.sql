-- {"query": "30.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 139} 
WITH RECURSIVE cte_posts_hierarchy AS (
    SELECT 
        Id,
        ParentId,
        Title,
        1 AS Level
    FROM 
        Posts
    WHERE 
        ParentId IS NULL
    UNION ALL
    SELECT 
        p.Id,
        p.ParentId,
        p.Title,
        c.Level + 1
    FROM 
        Posts p
    INNER JOIN cte_posts_hierarchy c ON p.ParentId = c.Id
)

SELECT 
    ph.Id AS PostId,
    ph.Title,
    ph.Level
FROM 
    cte_posts_hierarchy ph
WHERE 
    ph.Level <= 3
ORDER BY 
    ph.Level DESC;