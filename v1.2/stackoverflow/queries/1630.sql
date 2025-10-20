WITH RECURSIVE RecursiveEngagedUsers AS (
    -- Find active users who have parents answering their questions recursively (max 3 levels deep)
    SELECT 
        p.OwnerUserId, 
        p.Id AS QuestionId,
        1 AS depth
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0

    UNION ALL

    SELECT 
        a.OwnerUserId,
        p.Id,
        r.depth + 1
    FROM (
        SELECT
            a.OwnerUserId,
            a.ParentId
        FROM Posts a
        WHERE a.PostTypeId = 2 
          AND a.OwnerUserId IS NOT NULL 
          AND a.OwnerUserId > 0
    ) a
    INNER JOIN Posts p ON p.Id = a.ParentId
    INNER JOIN RecursiveEngagedUsers r ON r.QuestionId = p.Id
    WHERE r.depth < 3
)
SELECT
    r.OwnerUserId,
    r.QuestionId,
    r.depth
FROM RecursiveEngagedUsers r
GROUP BY
    r.OwnerUserId,
    r.QuestionId,
    r.depth;