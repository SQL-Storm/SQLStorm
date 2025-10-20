WITH differences_per_post AS (
    SELECT
        p.Id,
        p.Title,
        p.Score
    FROM posts p
)
SELECT
    d.Id,
    d.Title,
    d.Score
FROM differences_per_post d
GROUP BY
    d.Id,
    d.Title,
    d.Score;