-- {"query": "14073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 172790, "output_tokens": 73174} 
WITH cte AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Body, 
        p.OwnerUserId, 
        p.CreationDate, 
        p.LastActivityDate,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS post_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
),
post_activity AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Body, 
        p.OwnerUserId, 
        p.CreationDate, 
        p.LastActivityDate,
        CASE 
            WHEN DATEDIFF(p.LastActivityDate, p.CreationDate) < 30 THEN 'Recent'
            WHEN DATEDIFF(p.LastActivityDate, p.CreationDate) >= 30 AND DATEDIFF(p.LastActivityDate, p.CreationDate) < 90 THEN 'Intermediate'
            ELSE 'Mature'
        END AS activity_level
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT 
    cte.Id, 
    cte.Title, 
    cte.Body, 
    cte.OwnerUserId, 
    cte.CreationDate, 
    cte.LastActivityDate,
    COALESCE(pa.activity_level, 'New') AS activity_level,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.PostId = cte.Id AND v.VoteTypeId IN (2, 3)
    ) AS vote_count,
    (
        SELECT COUNT(*) 
        FROM Comments c
        WHERE c.PostId = cte.Id
    ) AS comment_count,
    CONCAT(
        CAST(ROUND(CAST(COALESCE(u.UpVotes, 0) AS FLOAT) / GREATEST(CAST(COALESCE(u.UpVotes, 0) AS FLOAT) + CAST(COALESCE(u.DownVotes, 0) AS FLOAT), 1), 2) * 100 AS VARCHAR(10)), '%'
    ) AS upvote_ratio
FROM cte
LEFT JOIN post_activity pa ON cte.Id = pa.Id
LEFT JOIN Users u ON cte.OwnerUserId = u.Id
ORDER BY cte.post_rank;