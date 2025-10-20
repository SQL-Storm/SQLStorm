WITH RECURSIVE RecursiveTaggedPosts AS (
    -- Base: questions with specific tags
    SELECT
        p.Id,
        p.Title,
        p.Body,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        0 AS Depth
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.Tags LIKE '%sql%'
    
    UNION ALL
    
    -- Recursive: answers to posts already found
    SELECT
        a.Id,
        a.Title,
        a.Body,
        a.CreationDate,
        a.Tags,
        a.OwnerUserId,
        r.Depth + 1 AS Depth
    FROM Posts a
    JOIN RecursiveTaggedPosts r
      ON a.ParentId = r.Id
    WHERE a.PostTypeId = 2
)
SELECT
    r.Id,
    r.Title,
    r.Body,
    r.CreationDate,
    r.Tags,
    r.OwnerUserId,
    r.Depth,
    COUNT(c.Id) AS CommentCount,
    MAX(c.CreationDate) AS LastCommentDate
FROM RecursiveTaggedPosts r
LEFT JOIN Comments c
  ON c.PostId = r.Id
GROUP BY
    r.Id,
    r.Title,
    r.Body,
    r.CreationDate,
    r.Tags,
    r.OwnerUserId,
    r.Depth
ORDER BY r.CreationDate DESC;