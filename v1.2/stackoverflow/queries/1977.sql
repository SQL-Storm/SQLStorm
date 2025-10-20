WITH RECURSIVE RecursivePostHierarchy AS (
    SELECT
        p.Id,
        p.ParentId,
        1 AS Level,
        ARRAY[p.Id] AS Path
    FROM Posts p
    WHERE p.ParentId IS NOT NULL

    UNION ALL

    SELECT
        p.Id,
        p.ParentId,
        r.Level + 1 AS Level,
        r.Path || ARRAY[p.Id] AS Path
    FROM Posts p
    JOIN RecursivePostHierarchy r
        ON p.ParentId = r.Id
)
SELECT
    r.Id,
    r.ParentId,
    r.Level,
    r.Path
FROM RecursivePostHierarchy r
ORDER BY r.Level, r.Id;