WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.OwnerUserId,
        u.DisplayName AS Owner_Name
    FROM posts p
    LEFT JOIN users u
        ON p.OwnerUserId = u.Id
)
SELECT
    Id,
    PostTypeId,
    Title,
    Tags,
    CreationDate,
    Score,
    ViewCount,
    AnswerCount,
    FavoriteCount,
    OwnerUserId,
    Owner_Name
FROM RankedPosts;