WITH RECURSIVE PeriodicTrivia AS (
    SELECT
        date_trunc('month', MIN(CreationDate)) AS per_start,
        (date_trunc('month', MIN(CreationDate)) + INTERVAL '1 month' - INTERVAL '1 second') AS per_end
    FROM Posts
    UNION ALL
    SELECT
        per_start + INTERVAL '1 month' AS per_start,
        (per_start + INTERVAL '2 month' - INTERVAL '1 second') AS per_end
    FROM PeriodicTrivia
    WHERE per_start + INTERVAL '1 month' <= (SELECT MAX(CreationDate) FROM Posts)
)
SELECT
    p.Id,
    p.CreationDate,
    pt.per_start,
    pt.per_end,
    COUNT(*) OVER (PARTITION BY pt.per_start, pt.per_end) AS posts_in_period
FROM Posts p
JOIN PeriodicTrivia pt
    ON p.CreationDate >= pt.per_start
    AND p.CreationDate <= pt.per_end
GROUP BY
    p.Id,
    p.CreationDate,
    pt.per_start,
    pt.per_end;