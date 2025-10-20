WITH RECURSIVE TagHierarchy AS (
    SELECT 
        Id,
        TagName,
        ExcerptPostId,
        WikiPostId
    FROM Tags
    WHERE Id IS NOT NULL
)
SELECT
    th.Id,
    th.TagName,
    th.ExcerptPostId,
    th.WikiPostId
FROM TagHierarchy th
GROUP BY
    th.Id,
    th.TagName,
    th.ExcerptPostId,
    th.WikiPostId;