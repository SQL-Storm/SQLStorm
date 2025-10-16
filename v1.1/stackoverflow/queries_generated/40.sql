-- {"query": "40.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 185} 

WITH cte AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)
SELECT
    cte.PostId,
    cte.Title,
    cte.Score,
    cte.ViewCount,
    cte.TotalVotes,
    u.DisplayName AS OwnerDisplayName
FROM cte
JOIN Users u ON u.Id = (
    SELECT TOP 1 ph.UserId
    FROM PostHistory ph
    WHERE ph.PostId = cte.PostId
    ORDER BY ph.CreationDate DESC
)
WHERE cte.TotalVotes > 10
ORDER BY cte.Score DESC, cte.ViewCount DESC;
