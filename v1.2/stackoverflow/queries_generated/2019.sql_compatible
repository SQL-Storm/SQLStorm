WITH RecursiveTagPaths AS (
    SELECT
        t.Id AS starting_tag,
        t.TagName AS current_tag,
        ARRAY[t.TagName] AS tag_path,
        1 AS level
    FROM Tags t
    WHERE t.TagName IS NOT NULL
)
SELECT *
FROM RecursiveTagPaths;