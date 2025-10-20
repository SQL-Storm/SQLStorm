WITH RecursiveCTE AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        t.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate) AS rn
    FROM
        posts p
    LEFT JOIN
        posttypes t ON t.Id = p.PostTypeId
)
SELECT
    Id,
    PostTypeId,
    OwnerUserId,
    Score,
    CreationDate,
    PostTypeName,
    rn
FROM
    RecursiveCTE;