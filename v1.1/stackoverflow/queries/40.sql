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
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount
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
    SELECT ph.UserId
    FROM PostHistory ph
    WHERE ph.PostId = cte.PostId
    ORDER BY ph.CreationDate DESC
    LIMIT 1
)
WHERE cte.TotalVotes > 10
ORDER BY cte.Score DESC, cte.ViewCount DESC;