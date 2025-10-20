WITH RECURSIVE RecursiveAnswerHierarchy AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ParentId,
        1 AS DepthPath,
        '-' || CAST(p.Id AS VARCHAR) || '-' AS PathNotIn,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.Id) AS rn_in_parent
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.ParentId IS NOT NULL

    UNION ALL

    SELECT
        c.Id,
        c.OwnerUserId,
        c.Score,
        c.ParentId,
        r.DepthPath + 1 AS DepthPath,
        r.PathNotIn || CAST(c.Id AS VARCHAR) || '-' AS PathNotIn,
        ROW_NUMBER() OVER (PARTITION BY c.ParentId ORDER BY c.Score DESC, c.Id) AS rn_in_parent
    FROM Posts c
    JOIN RecursiveAnswerHierarchy r ON r.Id = c.ParentId
    WHERE c.PostTypeId = 2
)
SELECT
    Id,
    OwnerUserId,
    Score,
    ParentId,
    DepthPath,
    PathNotIn,
    rn_in_parent
FROM RecursiveAnswerHierarchy;