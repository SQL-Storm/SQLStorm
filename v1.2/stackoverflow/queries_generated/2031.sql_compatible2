WITH RECURSIVE RecursiveUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.ParentId,
        p.Score,
        p.ViewCount,
        1 AS iteration
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)

    UNION ALL

    SELECT
        rup.UserId,
        rup.DisplayName,
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.Score,
        p.ViewCount,
        rup.iteration + 1
    FROM RecursiveUserPosts rup
    JOIN Posts p ON p.ParentId = rup.PostId
)
SELECT
    rup.UserId,
    rup.DisplayName,
    rup.PostId,
    rup.PostTypeId,
    rup.ParentId,
    rup.Score,
    rup.ViewCount,
    rup.iteration
FROM RecursiveUserPosts rup
GROUP BY
    rup.UserId,
    rup.DisplayName,
    rup.PostId,
    rup.PostTypeId,
    rup.ParentId,
    rup.Score,
    rup.ViewCount,
    rup.iteration
ORDER BY rup.UserId, rup.iteration, rup.PostId;