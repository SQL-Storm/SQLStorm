WITH Recursive_TopTags AS (
    SELECT tagtype.tagname
    FROM tags AS tagtype
    ORDER BY tagtype.count DESC
    LIMIT 50
)
SELECT *
FROM Recursive_TopTags;