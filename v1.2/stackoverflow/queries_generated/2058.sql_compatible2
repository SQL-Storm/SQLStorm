WITH votacao_data AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title
    FROM posts p
)
SELECT
    PostId,
    PostTypeId,
    Title
FROM votacao_data
GROUP BY
    PostId,
    PostTypeId,
    Title;