WITH RECURSIVE recursive_tags AS (
    -- extract tags from Posts.Tags which are like '<tag1><tag2>'
    SELECT
        p.Id AS post_id,
        CAST(NULL AS VARCHAR) AS tag,
        -- strip outer angle brackets if present
        CASE
            WHEN p.Tags IS NULL THEN ''
            WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2))
            ELSE p.Tags
        END AS rest
    FROM Posts p
    WHERE p.PostTypeId = 2
  UNION ALL
    SELECT
        post_id,
        -- next tag: substring up to first '><' or whole rest if no separator
        CASE
            WHEN POSITION('><' IN rest) > 0 THEN TRIM(SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1))
            ELSE TRIM(rest)
        END AS tag,
        -- remaining string after removing the extracted tag and the separator
        CASE
            WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
            ELSE ''
        END AS rest
    FROM recursive_tags
    WHERE rest <> ''
)
SELECT 
    t.tag AS tag_name,
    u.DisplayName,
    u.Location,
    u.Reputation,
    SUM(p.Score) AS total_score,
    COUNT(*) AS post_count,
    AVG(p.Score) AS avg_score,
    RANK() OVER (PARTITION BY t.tag ORDER BY SUM(p.Score) DESC) AS rank_within_tag
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN
    -- join to extracted tags for this post; filter out the initial seed rows where tag is NULL
    recursive_tags t ON t.post_id = p.Id AND t.tag IS NOT NULL AND t.tag <> ''
WHERE 
    p.PostTypeId = 2  -- Answers
    AND p.CreationDate >= CAST('2023-01-01' AS TIMESTAMP)
    AND p.CreationDate < CAST('2024-01-01' AS TIMESTAMP)
    AND p.Score > 0
    AND u.Reputation > 100
GROUP BY 
    t.tag, u.Id, u.DisplayName, u.Location, u.Reputation
HAVING 
    COUNT(*) >= 5
    AND SUM(p.Score) >= 100
ORDER BY 
    t.tag, rank_within_tag
LIMIT 10000;