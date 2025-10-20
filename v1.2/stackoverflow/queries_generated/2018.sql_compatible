WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        co.ID AS AcceptId,
        p.Score,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Comments co ON co.PostId = p.Id
    WHERE p.CreationDate IS NOT NULL
)
SELECT
    PostId,
    PostTypeId,
    AcceptId,
    Score,
    OwnerUserId,
    CreationDate,
    LastActivityDate,
    rn
FROM RankedPosts
WHERE rn = 1;