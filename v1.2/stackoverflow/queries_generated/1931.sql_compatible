WITH relevant_badges AS (
    SELECT
        gba.Id,
        gba.UserId,
        gba.Name,
        gba.Class,
        LOWER(gba.Name) AS lower_name,
        ROW_NUMBER() OVER (PARTITION BY gba.UserId ORDER BY gba.Date DESC) AS rn
    FROM Badges AS gba
)
SELECT
    rb.Id,
    rb.UserId,
    rb.Name,
    rb.Class,
    rb.lower_name,
    rb.rn
FROM relevant_badges AS rb
WHERE rb.rn = 1;