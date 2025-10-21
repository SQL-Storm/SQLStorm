WITH RECURSIVE cte AS (
    SELECT 
        p.Id AS post_id,
        p.Title AS post_title,
        COUNT(c.Id) AS comment_count
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title

    UNION ALL

    SELECT 
        p.Id AS post_id,
        p.Title AS post_title,
        COUNT(c.Id) AS comment_count
    FROM cte
    JOIN Posts p ON cte.post_id = p.ParentId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.Id, p.Title, cte.post_id
)
SELECT 
    post_id,
    post_title,
    comment_count
FROM cte
ORDER BY post_id;