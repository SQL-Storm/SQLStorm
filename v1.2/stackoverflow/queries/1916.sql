WITH RecursiveRestrictedTags AS (
    SELECT CAST(NULL AS text) AS tag
)
SELECT
    tag
FROM
    RecursiveRestrictedTags
GROUP BY
    tag;