WITH RECURSIVE RecursiveCte AS (
    SELECT p.Id, p.PostTypeId, p.ParentId, p.Title, p.Body, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId,
      dense_rank() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankPerType
    FROM Posts p
    WHERE p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
      AND p.OwnerUserId IS NOT NULL

    UNION ALL

    SELECT c.Id, c.PostTypeId, c.ParentId, c.Title, c.Body, c.Score, c.ViewCount, c.CreationDate, c.OwnerUserId, rsp.RankPerType + 10000
    FROM Posts c
    INNER JOIN RecursiveCte rsp ON rsp.Id = c.ParentId
    WHERE c.PostTypeId = 2 AND rsp.RankPerType < 100
),
BadgesCEq AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT b.Name) AS tag_cancel_badges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id
)
SELECT
    dp.Id,
    dp.PostTypeId,
    dp.ParentId,
    dp.Title,
    dp.Body,
    dp.Score,
    dp.ViewCount,
    dp.CreationDate,
    dp.OwnerUserId,
    dp.RankPerType,
    beq.tag_cancel_badges
FROM RecursiveCte dp
LEFT JOIN BadgesCEq beq ON beq.UserId = dp.OwnerUserId
GROUP BY
    dp.Id,
    dp.PostTypeId,
    dp.ParentId,
    dp.Title,
    dp.Body,
    dp.Score,
    dp.ViewCount,
    dp.CreationDate,
    dp.OwnerUserId,
    dp.RankPerType,
    beq.tag_cancel_badges;