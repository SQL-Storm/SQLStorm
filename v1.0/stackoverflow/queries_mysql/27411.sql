
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        p.Score,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS TagRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= NOW() - INTERVAL 1 YEAR 
    GROUP BY 
        p.Id, p.Title, p.Body, p.CreationDate, u.DisplayName, p.Score, p.Tags
),
TopQuestions AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Body,
        rp.OwnerDisplayName,
        rp.Score,
        rp.CommentCount,
        rp.TagRank
    FROM 
        RankedPosts rp
    WHERE 
        rp.TagRank <= 3 
)
SELECT 
    tq.Title,
    tq.Body,
    tq.OwnerDisplayName,
    tq.Score,
    tq.CommentCount,
    GROUP_CONCAT(DISTINCT t.TagName SEPARATOR ', ') AS AssociatedTags
FROM 
    TopQuestions tq
JOIN 
    Posts p ON tq.PostId = p.Id
JOIN 
    Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
GROUP BY 
    tq.Title, tq.Body, tq.OwnerDisplayName, tq.Score, tq.CommentCount
ORDER BY 
    tq.Score DESC, tq.CommentCount DESC
LIMIT 50;
