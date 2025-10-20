WITH calculation AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(u.Reputation, 0) AS OwnerReputation
    FROM posts p
    LEFT JOIN users u ON p.OwnerUserId = u.Id
)
SELECT
    PostId,
    PostTypeId,
    CreationDate,
    Score,
    ViewCount,
    OwnerReputation
FROM calculation;